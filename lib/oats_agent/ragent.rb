#require 'eventmachine' # http://eventmachine.rubyforge.org/EventMachine.html#M000486
#require 'patches_for_eventmachine_12.10'
require 'em-http-request' # https://github.com/igrigorik/em-http-request/wiki/Issuing-Requests
require 'json'

module OatsAgent

  class Ragent < EventMachine::Connection
    attr_accessor :job_count, :jid, :occ_reintroduction_wait_time
    attr_reader :request
    @@logger = nil
    @@oats_info_snapshot = {}
    @@job_count = 1
    @@occ_default = nil
    @@logger = Log4r::Logger.new('A')
    include EM::P::ObjectProtocol


    # Non-nil if in the state of requesting for the next job
    def Ragent.in_next_job
      @@in_next_job
    end
    def Ragent.in_next_job=(v)
      @@in_next_job = v
    end
    def Ragent.is_busy=(jid)
      @@is_busy = jid
    end
    # Current/Last jobid worked on, or false
    def Ragent.is_busy
      @@is_busy
    end

    # Contains YAML OCC entries if oats is started in agent mode
    def Ragent.occ
      @@occ_default
    end

    def Ragent.start(occ_def)
      @@occ_default = occ_def # This should not change during agent execution
      @@logger.add('console')
      3.times do |count| # In case of unexpected exceptions
        begin
          @@occ_reintroduction_wait_time = nil
          @@is_busy = false # If agent is started from scratch assume previous one is gone
          @@in_next_job = false
          @@logger.info "====================================================================================="
          mach_port = ENV['HOSTNAME'] + ':' + $oats['execution']['occ']['port'].to_s
          @@logger.info "Started OATS Server execution-#{count} on #{mach_port} at #{Time.now} "
          EventMachine::run do
            EventMachine::start_server @@occ_default['agent_host'], @@occ_default['agent_port'].to_i, Ragent
            EventMachine.next_tick do
              Ragent.server_logger nil,'Initiating contact with OCC '
              Ragent.start_next_job unless Ragent.is_busy
            end
          end
          break # Shutdown requested
        rescue Exception => exc
          @@logger.error exc
        end
      end
    end

    #  def Ragent.force_close_connection
    #  end
    def Ragent.job_count=(val)
      @@job_count = val
    end
    def Ragent.job_count
      @@job_count
    end

    def Ragent.snapshot_oats_info(oats_info)
      @@oats_info_snapshot = oats_info
    end

    # Generates summary data into the input oats_info
    def regen_results_summary!(oats_info)
      return Oats::Report.results(oats_info['test_files'],true)
    rescue
      server_logger $!.inspect + "\n" + $!.backtrace.join("\n  ")
      false
    end

    # Results_status: Early, Partial, Current, Archived, Missing, Error
    def get_oats_info
      if @request[:jobid] == Ragent.is_busy # working on it now
        if @request[:jobid] == @@oats_info_snapshot['jobid'] # first test started processing
          if regen_results_summary!(@@oats_info_snapshot) # summary succeeded
            oats_info = Marshal.load(Marshal.dump(@@oats_info_snapshot))
            oats_info['results_status'] = 'Partial'
          else
            server_logger "[ERROR] Can not regen_results_summary from the snapshot"
            oats_info = {'results_status' => 'Error'}
          end
        elsif @@oats_info_snapshot['jobid']
          msg = "ERROR: Unexpected condition. Request jobid: #{@request[:jobid]} does not match stored job id: #{@@oats_info_snapshot['jobid']}"
          server_logger msg
          oats_info = { 'jobid' => @request[:jobid], 'results_status' => 'Error', 'error_message' => msg }
        else
          oats_info = Marshal.load(Marshal.dump(Oats.context))
          oats_info['results_status'] = 'Early'
          oats_info['jobid'] = Ragent.is_busy
        end
      else # Search for request on disk in archive or results
        res_dir = File.join(Oats.result_archive_dir, @request[:jobid].to_s)
        results_file = File.join( res_dir,'results.dump')
        if File.readable?(results_file) # Archived ones should have summary
          oats_info = Oats::Report.oats_info_retrieve(results_file)
          oats_info['results_status'] = 'Archived'
        else # May have to regenerate the summary, in case test had died
          results_file = File.join( $oats['execution']['dir_results'], 'results.dump')
          if File.readable?(results_file)
            oats_info = Oats::Report.oats_info_retrieve(results_file)
            if regen_results_summary!(oats_info) and @request[:jobid] == oats_info['jobid']
              oats_info['results_status'] = 'Current'
            else
              oats_info = {} unless oats_info.instance_of?(Hash)
              oats_info['debug_message'] = "request_jobid: #{@request[:jobid]}, current oats_info jobid: #{oats_info['jobid']}"
              oats_info['results_status'] = 'Missing'
            end
          else
            oats_info = { 'results_status' => 'Missing' ,
              'debug_message' => "No readable: #{results_file}" }
          end
        end
      end
      # Convert object to hash
      oats_info['test_files'] = oats_info['test_files'].testlist_hash if oats_info['test_files']
      return oats_info
    rescue
      server_logger $!.inspect + "\n" + $!.backtrace.join("\n  ")
    end

    def receive_object(request)
      @request = request
      password = @request.delete(:password)
      server_logger "Received " + @request.inspect
      @request[:password] = password
      response = {}
      case @request[:command]

      when 'status'
        EventMachine.next_tick { run_next_job } unless Ragent.is_busy

      when 'start'
        if Ragent.is_busy
          server_logger "Not getting next job again because Ragent.is_busy: #{Ragent.is_busy}"
        else
          EventMachine.next_tick { run_next_job }
        end

      when 'results'
        begin
          response[:oats_info] = get_oats_info
        rescue
          server_logger $!.inspect + "\n" + $!.backtrace.join("\n  ")
        end

      when 'run' # only called from oats client, not from OCC
        EventMachine.defer( proc {
            Oats::Driver.start(@request[:jobid], @request[:args])
          } ) unless Ragent.is_busy

      when 'stop' # any further test execution for this jobid
        Oats.context['stop_oats'] = @request[:id] if @request[:stop_jobs].include?(Oats.context['jobid'])

      when 'shutdown'
      else
        response[:unknown_command] = true
        server_logger "Unknown command #{@request[:command]}"
      end
      response[:is_busy] = Ragent.is_busy
      stop_oats = Oats.context && Oats.context['stop_oats']
      response[:is_signal_oats_to_stop] = stop_oats if stop_oats
      server_logger "Sending " + response.inspect
      response[:password] = password
      send_object(response)
      close_connection_after_writing
    rescue
      server_logger $!.inspect + "\n" + $!.backtrace.join("\n  ")
    end

    def unbind
      if @request[:command] == 'shutdown'
        server_logger "Shutting down the server."
        EventMachine::stop_event_loop
      end
    end

    def run_next_job(prev_jobid = nil)
      return unless @request[:occ_host] # Bad input or invoked via client, not occ
      occ = @@occ_default.clone
      occ['server_host'] = @request[:occ_host]
      occ['server_port'] = @request[:occ_port]
      Ragent.start_next_job(occ, self, prev_jobid)
    end

    def self.start_next_job(occ = @@occ_default, ra = nil, prev_jobid = nil)
      if Ragent.in_next_job or Ragent.is_busy
        msg = if Ragent.in_next_job
          if Ragent.in_next_job  == nil.object_id
            "already getting the initial job."
          else
            "already getting job for #{Ragent.in_next_job}]"
          end
        else
          "became busy with #{Ragent.is_busy}"
        end
        Ragent.server_logger ra, "Not requesting new job since #{msg}"
        return false
      end
      Ragent.in_next_job = ra.object_id
      # Double check that this agent has the busy lock
      if not Ragent.in_next_job or Ragent.in_next_job != ra.object_id
        Ragent.server_logger(ra, "Not requesting new job since " +
            "now another Ragent #{ra.object_id} is requesting next job besides current #{Ragent.in_next_job}")
        return false
      end
      query = {
        'nickname' => occ['agent_nickname'],
        'machine' => occ['agent_host'],
        'port' => occ['agent_port'] }
      query['jobid'] = prev_jobid if prev_jobid
      query['repo'] = ENV['OATS_TESTS_CODE_VERSION'].to_s if ENV['OATS_TESTS_CODE_VERSION'] and ENV['OATS_TESTS_CODE_VERSION'] != ''
      query['logfile'] = File.basename(ENV['OATS_AGENT_LOGFILE']||'agent.log')
      Ragent.server_logger ra, "Getting next OCC job: " + query.inspect
      query['password='] = ra.request[:password] if ra and ra.request[:password]
      # Default inactivity_timeout of 10 is not enough when OCC is restarting too
      # many agents. Agent gives up in 10secs but OCC hands over the job in 20secs.
      # As a result OCC thinks job is received but agent has never seen the job.
      connection_options = { :connect_timeout => 60,:inactivity_timeout => 60}
      http_req = EventMachine::HttpRequest.new('http://' + occ['server_host'] + ":#{occ['server_port']}",connection_options)
      http = http_req.get :path => '/jobs/nxt', :query => query
      http.errback  { self.no_response(occ,ra, prev_jobid) }
      http.callback do
        status = http.response_header.status
        if status == 200
          data =http.response
          nxt_job = JSON.parse(data) if data
          if nxt_job['jid']
            Ragent.is_busy = nxt_job['jid']
            Ragent.in_next_job = false
            if ra
              ra.jid = nxt_job['jid']
              ra.occ_reintroduction_wait_time = nil # Reset wait time to default if heard from OCC
            end
            Ragent.server_logger ra, "Job-#{Ragent.job_count} #{nxt_job.inspect}"
            EventMachine.defer do
              begin
                opts= {'execution:environments' => [nxt_job['env']],
                  'execution:test_files' => [nxt_job['list']] }
                opts['_:options'] = nxt_job['options'].split(',') if nxt_job['options'] and nxt_job['options'] != ''
                Ragent.snapshot_oats_info({})
                Oats::Driver.start(nxt_job['jid'],opts)
              ensure
                Ragent.is_busy = false
              end
              Ragent.job_count += 1
              if ra
                ra.run_next_job(nxt_job['jid'] )
              else
                Ragent.start_next_job(occ,ra,nxt_job['jid'])
              end
            end
          else
            Ragent.in_next_job = false
            Ragent.server_logger ra, "No more pending jobs at OCC. Pausing processing.\n"
            Ragent.job_count = 1
            Ragent.server_logger ra, "***********************************************************\n"
          end
        else
          self.no_response(occ,ra, prev_jobid)
        end
      end
    rescue RuntimeError  => e.message
      Ragent.in_next_job = false
      if e.message == 'eventmachine not initialized: evma_connect_to_server'
        Ragent.server_logger ra, "Shutting down..."
      else
        Ragent.server_logger ra, $!.inspect + "\n" + $!.backtrace.join("\n  ")
      end
    end

    def self.no_response(occv,ra, prev_jobid)
      Ragent.in_next_job = false
      Ragent.server_logger ra, "OCC did not respond."
      wait = ra ? ra.occ_reintroduction_wait_time : @@occ_reintroduction_wait_time
      wait ||= $oats['execution']['occ']['timeout_waiting_for_occ']
      # Keep retrying to introduce, doubling the intervals
      self.server_logger ra, "Will retry in #{wait} seconds."
      EM.add_timer(wait) do
        Ragent.start_next_job(occv,ra, prev_jobid) unless Ragent.is_busy # by now
      end
      wait *= (1.5 + rand(101)/100.0)
      wait = wait.round
      if ra
        ra.occ_reintroduction_wait_time = wait
      else
        @@occ_reintroduction_wait_time = wait
      end
    end

    def server_logger(arg)
      Ragent.server_logger self, arg
    end

    def Ragent.server_logger(ra, arg)
      if ra
        req = ra.request
        jid = ra.jid
        rt = ":R#{(req and req[:id]) ? req[:id] : ra.object_id}"
        rt += "#{" J:#{jid}" if jid }"
      end
      @@logger.info "[RS#{rt}] #{arg}"
    rescue
      @@logger.error $!.inspect + "\n" + $!.backtrace.join("\n  ")
    end

  end
  
end

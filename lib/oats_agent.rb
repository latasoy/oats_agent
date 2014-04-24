#require 'rubygems'
unless ENV['HOSTNAME']
  if RUBY_PLATFORM =~ /(mswin|mingw)/
    ENV['HOSTNAME'] = ENV['COMPUTERNAME']
  else
    ENV['HOSTNAME'] = `hostname`.chomp
  end
end
ENV['HOSTNAME'] = ENV['HOSTNAME'].downcase
require 'win32ole' if RUBY_PLATFORM =~ /(mswin|mingw)/

module OatsAgent
  class << self

    def fkill(proc)
      if proc.instance_of? Hash
        pname = proc['cmd']
        pid = proc['pid']
        msg = " PID #{pid}: #{pname}"
      else
        pid = proc
      end
      $log.warn "Killing" + msg
      if RUBY_PLATFORM =~ /(mswin|mingw)/
        killed = Process.kill('KILL',pid.to_i)
        killed = 0 if RUBY_VERSION =~ /^1.9/ and killed.empty?
        $log.warn "Failed to kill" + msg if killed == 0
      else
        out = `kill -9 #{pid} 2>&1`
        $log.warn out unless out == ''
      end
    end
    
    def kill_matching(cmd_string)
      procs = []
      if RUBY_PLATFORM =~ /(mswin|mingw)/
        WIN32OLE.connect("winmgmts://").ExecQuery("select * from win32_process").each do |process|
          #          puts [process.Commandline, process.ProcessId, process.name].inspect
          procs.push 'pid' => process.ProcessId, 'cmd' => process.CommandLine if process.Commandline =~ /#{cmd_string}/
        end
        # Looking for port is too slow on windows
        #        lines = "netstat -#{RUBY_PLATFORM =~ /(mswin|mingw)/ ?  'a' : 'n' } -o"
        #        list = `#{lines}`.split(/\n/)
        #        list.each do |p|
        #          p =~ /:(\d+)\s+.*\s+LISTENING\s+(\d+)/
        #          next unless $1 and $1 == port
        #          procs.push({ 'pid' => $2, 'cmd' => 'LISTENING' }) 
        #        end
      else
        ps_cmd = "ps -ew -o pid=,ppid=,command="
        ps_list = `#{ps_cmd}`
        list = ps_list.split(/\n/)
        list.each do |p|
          next unless p =~ /#{cmd_string}/
          p =~ /(\d+)\s+(\d+)\s+(.*)/
          procs.push({ 'pid' => $1, 'ppid' => $2, 'cmd' => $3 }) 
        end
      end
      procs.each { |p| fkill(p) }
    end

    # Initiates process to run agent in the background
    #  Options Hash Keys:
    #    required: agent_nickname, agent_port, 
    #    optional: oats_user, test_directory, repository_version
      
    def spawn(options)
      nick = options["nickname"] || ENV['HOSTNAME']
      ENV['OATS_AGENT_NICKNAME'] = nick  # Not sure if this is used at all
      port = options["port"] || 3010
      port = port.to_s
      user = options["user"]
      repo_version = options["repository_version"]
      dir_tests = options["test_directory"] || ENV['OATS_TESTS']

      archive_dir = File.expand_path "results_archive", ENV['HOME']
      log_dir = "#{archive_dir}/#{nick}/agent_logs"
      log_file = "#{log_dir}/agent_#{Time.new.to_i}.log"
      config_file = "#{log_dir}/config-agent.txt"
      agent_log_file = "#{log_dir}/agent.log"
      params =  "-n #{nick} -p #{port}"
      
      agent_params = params.dup
      agent_params +=  " -r #{repo_version}" if repo_version
      agent_params +=  " -u #{user}" if user
      if options["agent_host"] and options["agent_host"] != ENV['HOSTNAME']
        if RUBY_PLATFORM =~ /(mswin|mingw)/
          cmd = "psexec.exe -d -i -n 10 -w " + archive_dir +
            ' -u qa -p ' + 'passwd' + ' \\\\' + options["agent_host"] +
            ' ruby oats_agent ' + agent_params.join(' ')
        else
          #  options['agent_host'] = ENV['HOSTNAME']
          cmd = "ssh " + options["agent_host"] + ' oats_agent ' + agent_params
        end
        $log.info "Issuing remote host request: #{cmd}"
        out = `#{cmd}`
        $log.info out unless out == ''
        return
      end
      
      
      FileUtils.mkdir_p(log_dir) unless File.exists?(log_dir)
      ENV['OATS_AGENT_LOGFILE'] = log_file

      ruby_cmd = File.expand_path('../oats_agent/start.rb', __FILE__) + ' ' + params
      
      # Need these off when called by OCC, otherwise the OCC values are inherited
      %w(RUBYOPT BUNDLE_BIN_PATH BUNDLE_GEMFILE).each { |e| ENV[e] = nil }
      # kill_matching ruby_cmd
      return if options["kill_agent"]
      if dir_tests
        if File.directory?(dir_tests + '/.svn') and ENV['OATS_TESTS_SVN_REPOSITORY']
          svn_out =nil
          $log.info "Requested OATS Version: #{repo_version}" if repo_version
          code_version = nil

          3.times do
            code_version = `svn info #{dir_tests} | sed -n 's/Last Changed Rev: *//p'`
            code_version = nil if code_version == ''
            break if code_version.nil? or (repo_version and code_version >= repo_version)
            cmd = "svn update #{dir_tests} 2>&1"
            svn_out = `#{cmd}`
            svn_out.chomp!
            $log.info svn_out
            case svn_out
              when /^At revision/
                code_version = svn_out.sub(/At revision *(\d+).*/, '\1')
              when /Cleanup/
              when /Could not resolve hostname/
                break
            end
            if code_version == ''
              code_version = nil
              sleep 3
            else
              break
            end
          end
          if svn_out.nil? and ENV['OATS_TESTS_SVN_REPOSITORY']
            $log.error "Could not update the code version " +(code_version || '') + (repo_version ? "to #{repo_version}" : '')
            exit 2
          end

        elsif ENV["$OATS_TESTS_GIT_REPOSITORY"]
          dir_tests = archive_dir + '/' + nick + '/oats_tests'
          `git clone git_rep dir_tests if File.directory?(dir_tests)`
          Dir.chdir dir_tests
          origin = ENV["$OATS_TESTS_GIT_REPOSITORY"] || 'origin'

          if repo_version
            2.times do
              # may detach HEAD, but it is OK
              out = `git checkout #{repo_version} 2>&1`
              break if status == 0
              if out == "fatal: reference is not a tree: #{repo_version}"
                $log.info "Need to pull requested version: #{repo_version} "
              else
                $log.info "$out"
              end
              $log.info `git pull #{origin} master` # fast-forward master from origin
            end
          else
            $log.info `git pull #{origin} master` # fast-forward master from origin
          end
          code_version = `git rev-list HEAD -1` # last commit in checked out version
          if code_version =~ /#{repo_version}/
            $log.info "Could not update the code version #{code_version} to #{repo_version}"
            exit 2
          end
          $log.info "Using OATS code version: #{code_version}" unless repo_version
        else
          code_version = repo_version
          $log.info "Setting OATS code version to the requested version: #{code_version}" if code_version
        end
      end
      ENV['OATS_TESTS_CODE_VERSION'] = code_version

      msg = ''
      msg += "User: #{user} " if user
      msg += "Repo version: #{repo_version} " if repo_version
      $log.info "#{msg}Starting: #{ruby_cmd}"
      if RUBY_PLATFORM =~ /(mswin|mingw)/
        archiv = ENV['HOME'] + '/results_archive'
        cmd = "psexec.exe -d -i -n 10 -w #{archiv} ruby #{ruby_cmd} 2>&1"
      else
        cmd = "#{ruby_cmd} >/dev/null 2>&1 &" 
      end
      out = `#{cmd}`
      $log.info out unless out == ''
      File.open(config_file, 'w') {|f| f.puts(nick +' '+ port) }

      10.times do
        if File.exist? log_file
          FileUtils.rm_f agent_log_file
          FileUtils.ln log_file, agent_log_file
          break
        end
        sleep 1
      end

    end
  end
end

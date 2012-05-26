#require 'rubygems'


module OatsAgent
  class << self

    def fkill(pid)
      if RUBY_PLATFORM =~ /(mswin|mingw)/
        `pskill #{pid} 2>&1`
      else
        `kill -9 #{pid} 2>&1`
      end
    end

    # Initiates process to run agent in the background
    #  Options Hash Keys:
    #    required: agent_nickname, agent_port, 
    #    optional: oats_user, test_directory, repository_version
      
    def spawn(options)
      nick = options["nickname"]
      raise " Must specify a machine nickname, exiting..." unless nick
      port = options["port"].to_s
      raise " Must specify a port, exiting..." unless port

      user = options["user"]
      repo_version = options["repository_version"]
      dir_tests = options["test_directory"] || ENV['OATS_TESTS']

      archive_dir = ENV['HOME'] + "/results_archive"
      log_dir = "#{archive_dir}/#{nick}/agent_logs"
      config_file = "#{log_dir}/config-agent.txt"
      log_file = "#{log_dir}/agent_#{Time.new.to_i}.log"
      agent_log_file = "#{log_dir}/agent.log"

      FileUtils.mkdir_p(log_dir) unless File.exists?(log_dir)
      ENV['OATS_AGENT_LOGFILE'] = log_file

      # Need these off when called by OCC, otherwise the OCC values are inherited
      %w(RUBYOPT BUNDLE_BIN_PATH BUNDLE_GEMFILE).each { |e| ENV[e] = nil }

      params =  "-n #{nick} -p #{port}"
      ps_cmd = "ps -ew -o pid=,ppid=,command= |grep 'ruby.*/start.rb #{params}' "
      ps_list = `#{ps_cmd}`
      list = ps_list.split(/\n/)
      procs = []
      list.each do |p|
        p =~ /(\d+)\s+(\d+)\s+(.*)/
        next if $3.include?('grep')
        procs.push({ 'pid' => $1, 'ppid' => $2, 'cmd' => $3 }) 
      end

      unless procs.empty?
        procs.each do |p|
          $log.info "Killing PID #{p['pid']}: " + p['cmd']
          out = fkill(p['pid'])
          $log.info out unless out == ''
        end
      end
      exit if options["kill_agent"]

      if File.directory?(dir_tests + '/.svn') and ENV['OATS_TESTS_SVN_REPOSITORY']
        svn_out =nil
        $log.info "Requested OATS Version: #{repo_version}" if repo_version
        code_version = nil
   
        3.times do
          code_version = `svn info #{dir_tests} | sed -n 's/Last Changed Rev: *//p'`
          code_version = nil if code_version == ''
          break if code_version.nil? or (repo_version and  code_version >= repo_version)
          cmd = "svn update #{dir_tests} 2>&1"
          svn_out = `#{cmd}`
          svn_out.chomp!
          $log.info svn_out
          case svn_out 
          when/^At revision/
            code_version = svn_out.sub(/At revision *(\d+).*/,'\1')
          when/Cleanup/
          when/Could not resolve hostname/
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
          $log.error "Could not update the code version " +( code_version || '') + ( repo_version ? "to #{repo_version}" : '')
          exit 2
        end

      elsif ENV["$OATS_TESTS_GIT_REPOSITORY"]
        dir_tests = archive_dir + ENV['OATS_AGENT_NICKNAME'] + '/oats_tests'
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
      ENV['OATS_TESTS_CODE_VERSION'] = code_version

      msg = ''
      msg += "User: #{user} " if user
      msg += "Repo version: #{repo_version} " if repo_version
      ruby_cmd = File.expand_path('../oats_agent/start.rb', __FILE__) + ' ' + params
      $log.info "#{msg}Starting: #{ruby_cmd}"
      cmd = "#{ruby_cmd} >> #{log_file} 2>&1 &" 
      out = `#{cmd}`
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

    def xx    
      cmd = ENV['OATS_AGENT_HOME'] ? (ENV['OATS_AGENT_HOME'] + '/bin/') : ''
      cmd += 'oats_agent'
      cmd += '.bat' if RUBY_PLATFORM =~ /(mswin|mingw)/
      cmd += " -u #{user.email}" 
      cmd += " -p #{port} -n #{nickname}"
      cmd += " -u #{user.email}" if user
      occ = Occ::Application.config.occ
      if RUBY_PLATFORM =~ /(mswin|mingw)/
        archiv = ENV['HOME'] + '/results_archive'
        remote_params = (name == occ['server_host']) ? '' : (' -u qa -p ' + occ['agent_mp'] + ' \\\\' + name)
        #      FileUtils.mkdir_p Oats.result_archive_dir
        "psexec.exe -d -i -n #{occ['timeout_waiting_for_agent']} -w #{archiv}" +
          remote_params + " #{occ['bash_path']} " + cmd
      else
        if name == ENV['HOSTNAME'] or name == occ['server_host']
          cmd
        else
          "ssh #{name} oats/bin/#{cmd}"
        end
      end
      Rails.logger.info "Issuing: #{com}"
      Rails.logger.info `#{com}`
    end
  
  end
end

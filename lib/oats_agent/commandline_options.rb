require 'optparse' # http://www.ruby-doc.org/stdlib/libdoc/optparse/rdoc/index.html
require 'log4r'  # http://log4r.sourceforge.net/rdoc/index.html

module OatsAgent

  module CommandlineOptions

    @@OPTIONS = nil
    def CommandlineOptions.options(argv = nil)

      begin

        # Hold all of the options parsed from the command-line by OptionParser.
        options = {}
        optparse = OptionParser.new do|opts|
          opts.banner = "Usage: oats.rb [options] test1 test2 ..."
          opts.separator "Options:"
          
          opts.on( '-p', '--port PORT', Integer,
            'Port number for the Oats Agent.' ) do |t|
            options['port'] = t if t
          end
          opts.on( '-n', '--nickname NICKNAME',
            'Nickname to display on OCC for the Oats Agent.' ) do |t|
            options['nickname'] = t if t
          end
          opts.on( '-u', '--user USER',
            'Sets OATS_USER for agent' ) do |t|
            options['user'] = t if t
          end
          opts.on( '-r', '--repository_version REPOSITORY_VERSION',
            'Repository version requested' ) do |t|
            options['repository_version'] = t
          end
          opts.on( '-a', '--agent_host HOSTNAME',
            'Hostname where the agent should start.' ) do |t|
            options['agent_host'] = t if t
          end
          opts.on( '-k', '--kill_agent',
            'Kill the agent.' ) do |t|
            options['kill_agent'] = true
          end
          opts.on( '-t', '--test_directory DIR_TESTS',
            'Test directory to override environment variable OATS_TESTS.' ) do |t|
            options['dir_tests'] = t
          end
          
          
          opts.on_tail( '-h', '--help', 'Display this screen' ) { $stderr.puts opts; exit }
        end

        optparse.parse!(argv)
        if argv and ! argv.empty?
          options['execution:test_files'] ||= []
          options['execution:test_files'] += argv
        end

      rescue Exception => e
        raise unless e.class.to_s =~ /^OptionParser::/
        $stderr.puts e.message
        $stderr.puts "Please type 'oats_agent -h' for valid options."
        exit 1
      end
      @@OPTIONS = options
    end

  end
end

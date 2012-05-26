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
            options['user'] = t
          end
          opts.on( '-r', '--repository_version',
            'Repository version requested' ) do |t|
            options['repository_version'] = t
          end
          opts.on( '-k', '--kill_agent',
            'Kill the agent.' ) do |t|
            options['kill_agent'] = true
          end
#          opts.on( '--run_agent',
#            'Run the agent in current process instead of spawning. Used internally' ) do |t|
#            options['run_agent'] = true
#          end
          opts.on( '-t', '--test_directory DIR_TESTS',
            'Test directory to override environment variable OATS_TESTS.' ) do |t|
            options['dir_tests'] = t
          end
          
          
          opts.on( '-i', '--ini INI_YAML_FILE',
            'The oats-user.yml to use.' ) do |t|
            options['_:ini_file'] = t
          end
          opts.on( '-o', '--options key11.key12.key13:val1,key21.key22:val2,...', Array,
            'Options to override values specified in oats.yml as well as other commandline options.' ) do |t|
            options['_:options'] = t
          end
          opts.on( '-j', '--json JSON',
            'The json hash to merge with oats data.' ) do |t|
            options['_:json'] = t
          end
          opts.on( '-q', '--quiet',
            'Do not echo anything to the console while running.' ) do |t|
            options['_:quiet'] = true
          end

          # Development options
          opts.on( '-g', '--gemfile GEMFILE',
            'Gemfile path to be included.' ) do |t|
            options['_:gemfile'] = t
          end
          opts.on( '-d' , '--d_options unit_test_dir1,unit_test_dir2', Array,
            'NetBeans passes these d options to TestUnit.' ) do |t|
            options['_:d_options'] = t
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

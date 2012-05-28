# OatsAgent

With this gem OATS can start in agent mode in the background so that it can 
communicate with OCC.

For more information on OATS and OCC see the READMEs in
     https://github.com/latasoy/oats
     https://github.com/latasoy/occ

## Installation

Install this gem on the machines that will have OATS agents.

    $ gem install oats_agent


## Usage

   Register the OATS agent with OCC:
    $ oats_agent -n <agent_nickname> -p <agent_port>


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

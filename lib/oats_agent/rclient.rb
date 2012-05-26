module OatsAgent

  class Rclient < EventMachine::Connection
    attr_reader :response
    include EM::P::ObjectProtocol
    #  def serializer
    #    YAML
    #  end
    #
    def initialize(host, request)
      @host = host
      @request = request
    end

    def receive_object(response)
      @response = response
      password = response.delete(:password)
      length = 500
      resp = response.inspect
      resp = resp[0..length] + ' ..... ' + resp[-length..-1] if resp.size > 2*length
      client_logger "Received " + resp + " from"
      response[:password] = password
      client_logger "Command was not recognized" if response[:unknown_command]
    end

    def client_logger(arg)
      $log.info arg + " #{@request[:id]}@#{@host} at " + Time.now.strftime("%y-%m-%d %H:%M:%S")
    end

    def post_init
      password = @request.delete(:password)
      client_logger "Sending " + @request.inspect + " to"
      @request[:password] = password
      send_object(@request)
    end
    def unbind
      client_logger "Did not hear from " unless @response
      EventMachine::stop_event_loop
    end
  end

end


module ZMQMachine
  
  module Server
    
    module RoutingEnvelope
      # Saves the return routing information for XREP sockets
      def save_routing messages
        @routing_messages = []
        @routing_strings = []
        messages.each do |message|
          string = message.copy_out_string
          @routing_strings << string
          @routing_messages << ZMQ::Message.new(string)
        end

        @routing_messages
      end

      def routing_strings
        @routing_strings.dup
      end
    end
    
  end
end

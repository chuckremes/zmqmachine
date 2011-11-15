
module ZMQMachine

  module Server

    module SUB
      include Base
      
      def initialize configuration
        @topic = configuration.topic || ''
        super
      end

      def write messages
        # no op
        close messages
      end


      private

      def allocate_socket
        @socket = @reactor.sub_socket(self)
      end

      def register_for_events socket
        subscribe socket, @topic

        super
      end

      def subscribe socket, topic
        rc = socket.subscribe topic
      end


    end # module SUB

  end # module Server
end # ZMQMachine

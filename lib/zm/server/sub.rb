
module ZMQMachine

  module Server

    module SUB
      include Base
      
      def initialize configuration
        @topic = configuration.topic
        super
      end

      def write messages
        # no op
        close messages
      end
      
      def add_subscription_filter(string)
        subscribe(@socket, string)
      end
      
      def remove_subscription_filter(string)
        unsubscribe(@socket, string)
      end


      private

      def allocate_socket
        @socket = @reactor.sub_socket(self)
      end

      def register_for_events socket
        subscribe socket, @topic if @topic

        super
      end

      def subscribe socket, topic
        rc = socket.subscribe topic.to_s
      end
      
      def unsubscribe socket, topic
        rc = socket.unsubscribe topic.to_s
      end


    end # module SUB

  end # module Server
end # ZMQMachine

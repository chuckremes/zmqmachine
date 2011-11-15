
module ZMQMachine

  module Server

    module PUB
      include Base

      private

      def allocate_socket
        @socket = @reactor.pub_socket(self)
      end

      def register_for_events socket
        @reactor.deregister_readable socket
        @reactor.deregister_writable socket
      end

    end # module PUB

  end # module Server
end # ZMQMachine

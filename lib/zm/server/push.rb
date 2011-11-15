
module ZMQMachine

  module Server

    module PUSH
      include Base

      private

      def allocate_socket
        @socket = @reactor.push_socket(self)
      end

      def register_for_events socket
        @reactor.deregister_readable socket
        @reactor.deregister_writable socket
      end

    end # module PUSH

  end # module Servers
end # ZMQMachine

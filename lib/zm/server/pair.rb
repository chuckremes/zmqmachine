
module ZMQMachine

  module Server

    module Pair
      include Base

      private

      def allocate_socket
        @socket = @reactor.pair_socket(self)
      end

      def register_for_events socket
        @reactor.register_readable socket
        @reactor.register_writable socket
      end

    end # module Pair

  end # module Server
end # ZMQMachine

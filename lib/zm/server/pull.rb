
module ZMQMachine

  module Server

    module PULL
      include Base

      def write messages
        # no op
        close messages
      end


      private

      def allocate_socket
        @socket = @reactor.pull_socket(self)
      end

    end # module PULL

  end # module Server
end # ZMQMachine

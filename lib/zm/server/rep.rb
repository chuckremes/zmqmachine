
module ZMQMachine

  module Server

    module REP
      include Base

      private

      def allocate_socket
        @socket = @reactor.rep_socket(self)
      end
    end # module REP


    module XREP
      include Base
      include RoutingEnvelope

      def on_readable socket, messages, envelope
        @routing = save_routing envelope

        @on_read.call socket, messages, envelope
        close_messages(envelope + messages)
      end


      private

      def allocate_socket
        @socket = @reactor.xrep_socket(self)
      end
    end # module XREP


    module ROUTER
      include XREP
    end # module ROUTER

  end # module Server
end # ZMQMachine


module ZMQMachine

  module Server

    module REQ
      include Base

      private

      def allocate_socket
        @socket = @reactor.req_socket(self)
      end

    end # module REQ

    module XREQ
      include Base

      def on_readable socket, messages, envelope
        if @reactor.reactor_thread?
          @on_read.call socket, messages, envelope
        else
          STDERR.print("error, #{self.class} Thread violation! Expected [#{Reactor.current_thread_name}] but got [#{Thread.current['reactor-name']}]\n")
        end
        close_messages(envelope + messages)
      end

      private

      def allocate_socket
        @socket = @reactor.xreq_socket(self)
      end

    end # module XREQ

    module DEALER
      include XREQ
    end # module DEALER

  end # module Server
end # ZMQMachine

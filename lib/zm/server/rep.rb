
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
        @socket = @reactor.xrep_socket(self)
      end
    end # module XREP


    module ROUTER
      include XREP
    end # module ROUTER

  end # module Server
end # ZMQMachine

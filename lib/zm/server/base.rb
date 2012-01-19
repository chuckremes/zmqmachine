
module ZMQMachine

  module Server

    module Base
      def initialize configuration
        @reactor = configuration.reactor
        @configuration = configuration

        @on_read = @configuration.on_read
        allocate_socket

        @message_queue = []
      end

      def shutdown
        @reactor.log :debug, "#{self.class}#shutdown_socket, closing reactor socket"
        @on_read = nil
        @reactor.close_socket(@socket)
      end

      def on_attach socket
        # socket options *must* be set before we bind/connect otherwise they are ignored
        set_options socket
        rc = -1

        if @configuration.bind
          rc = socket.bind @configuration.endpoint
          @reactor.log :debug, "#{self.class}#on_attach, bind rc [#{rc}], endpoint #{@configuration.endpoint}"
          raise "#{self.class}#on_attach, failed to bind to endpoint [#{@configuration.endpoint}]" unless ZMQ::Util.resultcode_ok?(rc)
        elsif @configuration.connect
          rc = socket.connect @configuration.endpoint
          @reactor.log :debug, "#{self.class}#on_attach, connect rc [#{rc}], endpoint #{@configuration.endpoint}"
          raise "#{self.class}#on_attach, failed to connect to endpoint [#{@configuration.endpoint}]" unless ZMQ::Util.resultcode_ok?(rc)
        end


        register_for_events socket
      end

      # Takes an array of ZM::Message instances and writes them out to the socket. If any
      # socket write fails, the message is saved. We will attempt to write it again in
      # 10 milliseconds or when another message array is sent, whichever comes first.
      #
      # All messages passed here are guaranteed to be written in the *order they were
      # received*.
      #
      def write messages, verbose = false
        if @reactor.reactor_thread?
          @verbose = verbose
          @message_queue << messages
          write_queue_to_socket
        end
      end

      # Prints each message when global debugging is enabled.
      #
      # Forwards +messages+ on to the :on_read callback given in the constructor.
      #
      def on_readable socket, messages
        if @reactor.reactor_thread?
          @on_read.call socket, messages
        else
          STDERR.print("error, #{self.class} Thread violation! Expected [#{Reactor.current_thread_name}] but got [#{Thread.current['reactor-name']}]\n")
        end
        close_messages messages
      end

      # Just deregisters from receiving any further write *events*
      #
      def on_writable socket
        #@reactor.log :debug, "#{self.class}#on_writable, deregister for writes on sid [#{@session_id}]"
        @reactor.deregister_writable socket
      end

      def on_readable_error socket, return_code
        STDERR.puts "#{self.class}#on_readable_error, rc [#{return_code}], errno [#{ZMQ::Util.errno}], description [#{ZMQ::Util.error_string}], sock #{socket.inspect}"
      end

      def on_writable_error socket, return_code
        STDERR.puts "#{self.class}#on_writable_error, rc [#{return_code}], errno [#{ZMQ::Util.errno}], description [#{ZMQ::Util.error_string}], sock #{socket.inspect}"
      end


      private


      def register_for_events socket
        @reactor.register_readable socket
        @reactor.deregister_writable socket
      end

      if ZMQ::LibZMQ.version2?

        def set_options socket
          socket.raw_socket.setsockopt ZMQ::HWM, (@configuration.hwm || 0)
          socket.raw_socket.setsockopt ZMQ::LINGER, (@configuration.linger || 1)
        end

      elsif ZMQ::LibZMQ.version3?

        def set_options socket
          socket.raw_socket.setsockopt ZMQ::RCVHWM, (@configuration.hwm || 0)
          socket.raw_socket.setsockopt ZMQ::SNDHWM, (@configuration.hwm || 0)
          socket.raw_socket.setsockopt ZMQ::LINGER, (@configuration.linger || 1)
        end

      end

      def write_queue_to_socket
        until @message_queue.empty?
          messages = get_next_message_array

          rc = @socket.send_messages messages

          if ZMQ::Util.resultcode_ok?(rc) # succeeded, so remove the message from the queue
            @message_queue.shift
            close_messages messages
          elsif ZMQ::Util.errno == ZMQ::EAGAIN
            # schedule another write attempt in 10 ms; break out of the loop
            @reactor.log :debug, "#{self.class}#write_queue_to_socket, failed to write messages; scheduling next attempt"
            STDERR.print("debug, #{self.class}#write_queue_to_socket, failed to write messages; scheduling next attempt\n")
            @reactor.oneshot_timer 10, method(:write_queue_to_socket)
            break
          end
        end
      end

      def get_next_message_array
        messages = @message_queue.at(0)
        messages.each { |message| @reactor.log :write, message.copy_out_string } if @verbose
        messages
      end

      def close_messages messages
        messages.each { |message| message.close }
      end

      def allocate_socket() nil; end

    end # module Base

  end # module Server

end # ZMQMachine

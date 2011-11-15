
module ZMQMachine

  module Socket

    # Two socket types (XREQ/XREP also called DEALER/ROUTER) have message
    # parts for routing the message to the appropriate destination. This
    # extra routing data is commonly called the routing envelope.
    #
    # The module provides logic for separating the routing envelope from
    # the message body. The envelope is passed separately to the user's
    # #on_readable method.
    #
    module EnvelopeHelp

      # Convenience method for sending a multi-part message. The
      # +messages+ and +envelope+ arguments must implement Enumerable.
      #
      def send_messages messages, envelope = nil
        envelope ? @raw_socket.sendmsgs(envelope + messages) : @raw_socket.sendmsgs(messages)
      end

      # Used by the reactor. Never called by user code.
      #
      def resume_read
        rc = 0
        more = true

        while ZMQ::Util.resultcode_ok?(rc) && more
          parts, envelope = [], []
          rc = @raw_socket.recv_multipart parts, envelope, ZMQ::Util.nonblocking_flag

          if ZMQ::Util.resultcode_ok?(rc)
            @handler.on_readable self, parts, envelope
          else
            # verify errno corresponds to EAGAIN
            if eagain?
              more = false
            elsif valid_socket_error?
              @handler.on_readable_error self, rc
            end
          end
        end
      end

    end # module EnvelopeSeparation

  end # Socket
end # ZMQMachine

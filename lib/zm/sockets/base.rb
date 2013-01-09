#--
#
# Author:: Chuck Remes
# Homepage::  http://github.com/chuckremes/zmqmachine
# Date:: 20100602
#
#----------------------------------------------------------------------------
#
# Copyright (C) 2010 by Chuck Remes. All Rights Reserved.
# Email: cremes at mac dot com
#
# (The MIT License)
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#---------------------------------------------------------------------------
#
#

module ZMQMachine

  module Socket

    module Base
      attr_reader :raw_socket, :kind
      attr_reader :poll_options

      def self.create context, handler
        socket = nil
        begin
          socket = new context, handler
        rescue => e
          socket = nil
        end

        socket
      end

      def initialize context, handler
        @context = context
        @bindings = []
        @connections = []

        @handler = handler
        @raw_socket = allocate_socket @context

        # default ZMQ::LINGER to 1 millisecond so closing a socket
        # doesn't block forever
        rc = @raw_socket.setsockopt ZMQ::LINGER, 1
        raise SetsockoptError.new("Setting LINGER on socket failed at line #{caller(0)}") unless ZMQ::Util.resultcode_ok?(rc)
        attach @handler
      end

      # Call the handler's #on_attach method and pass itself
      # so the handler may complete its setup.
      #
      # The #on_attach method is passed a single argument named
      # +socket+. The method should probably #bind or #connect
      # to an address and potentially schedule (via timer) an
      # operation or begin sending messages immediately.
      #
      def attach handler
        raise ArgumentError, "Handler must provide an 'on_attach' method" unless handler.respond_to? :on_attach
        handler.on_attach self
      end

      def close
        @raw_socket.close
        @raw_socket = nil
      end

      # Creates a 0mq socket endpoint for the transport given in the
      # +address+. Other 0mq sockets may then #connect to this bound
      # endpoint.
      #
      def bind address
        @bindings << address
        rc = @raw_socket.bind address.to_s
        @bindings.pop unless ZMQ::Util.resultcode_ok?(rc)
        rc
      end

      # Connect this 0mq socket to the 0mq socket bound to the endpoint
      # described by the +address+.
      #
      def connect address
        @connections << address
        rc = @raw_socket.connect address.to_s
        @connections.pop unless ZMQ::Util.resultcode_ok?(rc)
        rc
      end

      # Called to send a ZMQ::Message that was populated with data.
      #
      # Returns 0+ on success, -1 for failure. Use ZMQ::Util.resultcode_ok? and
      # ZMQ::Util.errno to check for errors.
      #
      def send_message message, multipart = false
        flag = multipart ? (ZMQ::SNDMORE | ZMQ::NonBlocking) : ZMQ::NonBlocking
        @raw_socket.sendmsg(message, flag)
      end

      # Convenience method to send a string on the socket. It handles
      # the creation of a ZMQ::Message and populates it appropriately.
      #
      # Returns 0+ for success, -1 for failure. Check ZMQ::Util.errno for
      # details on the error.
      #
      def send_message_string message, multipart = false
        @raw_socket.send_string message, ZMQ::NonBlocking | (multipart ? ZMQ::SNDMORE : 0)
      end

      # Convenience method for sending a multi-part message. The
      # +messages+ argument must implement Enumerable.
      #
      # Caller is responsible for closing the +messages+ upon return.
      #
      def send_messages messages
        @raw_socket.sendmsgs messages
      end

      if ZMQ::LibZMQ.version2? || ZMQ::LibZMQ.version3?

        # Retrieve the IDENTITY value assigned to this socket.
        #
        def identity() @raw_socket.identity; end

        # Assign a custom IDENTITY value to this socket. Limit is
        # 255 bytes and must be greater than 0 bytes.
        #
        def identity=(value) @raw_socket.identity = value; end

      end # version check

      # Used by the reactor. Never called by user code.
      #
      def resume_read
        if @raw_socket
          rc = 0
          more = true

          while ZMQ::Util.resultcode_ok?(rc) && more
            parts = []
            rc = @raw_socket.recvmsgs parts, ZMQ::NonBlocking

            if ZMQ::Util.resultcode_ok?(rc)
              @handler.on_readable self, parts
            else
              # verify errno corresponds to EAGAIN
              if eagain?
                more = false
              elsif valid_socket_error?
                STDERR.print("#{self.class} Received a valid socket error [#{ZMQ::Util.errno}], [#{ZMQ::Util.error_string}]\n")
                @handler.on_readable_error self, rc
              else
                STDERR.print("#{self.class} Unhandled read error [#{ZMQ::Util.errno}], [#{ZMQ::Util.error_string}]\n")
              end
            end
          end
        end
      end

      # Used by the reactor. Never called by user code.
      #
      def resume_write
        if @raw_socket
          @handler.on_writable self
        end
      end

      def inspect
        "kind [#{@kind}] poll options [#{@poll_options}]"
      end


      private

      def eagain?
        ZMQ::EAGAIN == ZMQ::Util.errno
      end

      def valid_socket_error?
        errno = ZMQ::Util.errno

        ZMQ::ENOTSUP  == errno ||
        ZMQ::EFSM     == errno ||
        ZMQ::ETERM    == errno ||
        ZMQ::ENOTSOCK == errno ||
        ZMQ::EINTR    == errno ||
        ZMQ::EFAULT   == errno
      end

    end # module Base

  end # module Socket

end # module ZMQMachine

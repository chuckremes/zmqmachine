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

      def initialize context, handler
        @state = :init
        @context = context
        @bindings = []
        @connections = []

        @handler = handler
        @raw_socket = allocate_socket @context
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

      # Creates a 0mq socket endpoint for the transport given in the
      # +address+. Other 0mq sockets may then #connect to this bound
      # endpoint.
      #
      def bind address
        begin
          @bindings << address
          @raw_socket.bind address.to_s
          true
        rescue ZMQ::ZeroMQError
          @bindings.pop
          false
        end
      end

      # Connect this 0mq socket to the 0mq socket bound to the endpoint
      # described by the +address+.
      #
      def connect address
        begin
          @connections << address
          @raw_socket.connect address.to_s
          true
        rescue ZMQ::ZeroMQError
          @connections.pop
          false
        end
      end

      # Called to send a ZMQ::Message that was populated with data.
      #
      # Returns true on success, false otherwise.
      #
      def send_message message
        rc = @raw_socket.send message, ZMQ::NOBLOCK
        rc
      end

      # Convenience method to send a string on the socket. It handles
      # the creation of a ZMQ::Message and populates it appropriately.
      #
      # Returns true on success, false otherwise.
      #
      def send_message_string message
        rc = @raw_socket.send_string message, ZMQ::NOBLOCK
        rc
      end

      # Used by the reactor. Never called by user code.
      #
      def resume_read
        message = ZMQ::Message.new
        rc = @raw_socket.recv message, ZMQ::NOBLOCK

        if rc
          @state = :ready
          @handler.on_readable self, message
        else
          @handler.on_readable_error self, rc
        end
      end

      # Used by the reactor. Never called by user code.
      #
      def resume_write
        @state = :ready
        @handler.on_writable self
      end

      def inspect
        "kind [#{@kind}] poll options [#{@poll_options}] state [#{@state}]"
      end


      private

      def ready_state?
        :ready == @state
      end

    end # module Base

  end # module Socket

end # module ZMQMachine

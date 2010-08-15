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
      # May raise a ZMQ::SocketError.
      #
      def send_message message, multipart = false
        queued = @raw_socket.send message, ZMQ::NOBLOCK | (multipart ? ZMQ::SNDMORE : 0)
        queued
      end

      # Convenience method to send a string on the socket. It handles
      # the creation of a ZMQ::Message and populates it appropriately.
      #
      # Returns true on success, false otherwise.
      #
      # May raise a ZMQ::SocketError.
      #
      def send_message_string message
        queued = @raw_socket.send_string message, ZMQ::NOBLOCK
        queued
      end
      
      # Convenience method for sending a multi-part message. The
      # +messages+ argument must respond to :size and :at (like
      # an Array).
      #
      # May raise a ZMQ::SocketError.
      #
      def send_messages messages
        rc = false
        i = 0
        size = messages.size
       
        # loop through all messages but the last
        while size > 1 && i < size - 1 do
          rc = send_message messages.at(i), true
          i += 1
        end
        
        # send the last message without the multipart arg to flush
        # the message to the 0mq queue
        rc = send_messages.last if size > 0
        rc
      end

      # Retrieve the IDENTITY value assigned to this socket.
      #
      def identity() @raw_socket.identity; end

      # Assign a custom IDENTITY value to this socket. Limit is
      # 255 bytes and must be greater than 0 bytes.
      #
      def identity=(value) @raw_socket.identity = value; end

      # Used by the reactor. Never called by user code.
      #
      # FIXME: need to rework all of this +rc+ stuff. The underlying lib returns
      # nil when a NOBLOCK socket gets EAGAIN. It returns true when a message
      # was successfully dequeued. The use of rc here is really ugly and wrong.
      #
      def resume_read
        messages = []
        rc = read_message_part messages

        while 0 == rc && @raw_socket.more_parts?
          rc = read_message_part messages
        end

        # only deliver the messages when rc is 0; otherwise, we
        # may have gotten EAGAIN and no message was read;
        # don't deliver empty messages
        deliver messages, rc unless 0 == rc
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

      def read_message_part messages
        message = ZMQ::Message.new
        begin
          rc = @raw_socket.recv message, ZMQ::NOBLOCK
          rc = 0 if rc
        rescue ZMQ::ZeroMQError => e
          rc = e
        end
        messages << message
        rc
      end

      def deliver messages, rc
        if 0 == rc
          @state = :ready
          @handler.on_readable self, messages
        else
          @handler.on_readable_error self, rc
        end
      end

    end # module Base

  end # module Socket

end # module ZMQMachine

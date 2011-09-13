#--
#
# Author:: Chuck Remes
# Homepage::  http://github.com/chuckremes/zmqmachine
# Date:: 20110721
# 
#----------------------------------------------------------------------------
#
# Copyright (C) 2011 by Chuck Remes. All Rights Reserved.
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

    class Push
      include ZMQMachine::Socket::Base

      def initialize context, handler
        @poll_options = ZMQ::POLLOUT
        @kind = :push

        super
      end

      # Attach a handler to the PUSH socket.
      #
      # A PUSH socket may *only* send messages.
      #
      # This socket expects its +handler+ to
      # implement the #on_writable methods.
      # The #on_writable method will be called whenever a
      # message may be enqueued without blocking.
      #
      # For error handling purposes, the handler must also
      # implement #on_writable_error.
      #
      def on_attach handler
        raise ArgumentError, "Handler must implement an #on_writable method" unless handler.respond_to? :on_writable
        raise ArgumentError, "Handler must implement an #on_writable_error method" unless handler.respond_to? :on_writable_error
        super
      end

      private

      def allocate_socket context
        sock = ZMQ::Socket.new context.pointer, ZMQ::PUSH
        sock
      end
    end # class Push

  end # module Socket

end # module ZMQMachine

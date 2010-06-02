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

    class Rep
      include ZMQMachine::Socket::Base

      def initialize context, handler
        @poll_options = ZMQ::POLLIN
        @kind = :reply

        super
        @state = :ready
      end

      # Attach a handler to the REP socket.
      #
      # A REP socket must alternate between recv.send (i.e.
      # it cannot receive twice in a row without an intervening
      # send). This socket expects its +handler+ to
      # implement at least the #on_readable method. This method
      # will be called whenever a request arrives.
      #
      # For error handling purposes, the handler must also
      # implement #on_readable_error.
      #
      def on_attach handler
        raise ArgumentError, "Handler must implement an #on_readable method" unless handler.respond_to? :on_readable
        raise ArgumentError, "Handler must implement an #on_readable_error method" unless handler.respond_to? :on_readable_error
        super
      end

      # +timeout+ is measured in milliseconds; default is 0 (never timeout)
      def send_message message
        unless waiting_for_request?
          rc = super
          @state = :waiting_for_request
        else
          rc = -1
        end

        rc
      end


      private

      def waiting_for_request?
        :waiting_for_request == @state
      end

      def allocate_socket context
        sock = ZMQ::Socket.new context.pointer, ZMQ::REP
        sock
      end
    end # class Rep

  end # module Socket

end # module ZMQMachine

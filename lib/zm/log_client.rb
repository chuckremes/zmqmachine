#--
#
# Author:: Chuck Remes
# Homepage::  http://github.com/chuckremes/zmqmachine
# Date:: 20110306
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

  class LogClient
    def initialize reactor, transport
      @reactor = reactor
      @transport = transport
      allocate_socket
      @message_queue = []
      @timer = nil
    end

    def shutdown
      @timer.cancel if @timer
      @reactor.close_socket @socket
    end

    def on_attach socket
      socket.identity = "#{Kernel.rand(999_999_999)}.#{socket.kind}.log_client"

      # socket options *must* be set before we bind/connect otherwise they are ignored
      set_options socket

      #FIXME error check!
      rc = socket.connect @transport

      raise "#{self.class}#on_attach, failed to connect to transport endpoint [#{@transport}]" unless rc

      register_for_events socket
    end

    # Takes an array of ZM::Message instances and writes them out to the socket. If any
    # socket write fails, the message is saved. We will attempt to write it again in
    # 10 milliseconds or when another message array is sent, whichever comes first.
    #
    # All messages passed here are guaranteed to be written in the *order they were
    # received*.
    #
    def write messages
      @message_queue << messages
      write_queue_to_socket
    end

    # Prints each message when global debugging is enabled.
    #
    # Forwards +messages+ on to the :on_read callback given in the constructor.
    #
    def on_readable socket, messages
      @on_read.call messages, socket
    end

    # Just deregisters from receiving any further write *events*
    #
    def on_writable socket
      @reactor.deregister_writable socket
    end


    private

    def allocate_socket
      @socket = @reactor.pub_socket self
    end

    def register_for_events socket
      @reactor.register_readable socket
      @reactor.deregister_writable socket
    end

    def set_options socket
      socket.raw_socket.setsockopt ZMQ::HWM, 0
      socket.raw_socket.setsockopt ZMQ::LINGER, 0
    end

    def write_queue_to_socket
      until @message_queue.empty?
        rc = @socket.send_messages @message_queue.at(0)

        if rc # succeeded, so remove the message from the queue
          messages = @message_queue.shift
          messages.each { |message| message.close }
          
          if @timer
            @timer.cancel
            @timer = nil
          end
          
        else
          
          # schedule another write attempt in 10 ms; break out of the loop
          # only set the timer *once*
          @timer = @reactor.oneshot_timer 10, method(:write_queue_to_socket) unless @timer
          break
        end
      end
    end

  end # class LogClient

end # module ZMQMachine

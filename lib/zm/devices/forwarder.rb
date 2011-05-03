#--
#
# Author:: Chuck Remes
# Homepage::  http://github.com/chuckremes/zmqmachine
# Date:: 20100823
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

  module Device


    # Used in conjunction with PUB/SUB sockets to allow multiple publishers to
    # all publish to the same "bus."
    #
    # The basic mechanics are that the program contains 1 (or more) publishers that
    # broadcast to the same bus. Connecting to
    # an intermediate queue device allows for the publishers to have all of their
    # traffic aggregated to a single port.
    #
    # Example:
    #
    #  # the queue creates sockets and binds to both given addresses; all messages get
    #  # republished from +incoming+ to +outgoing+
    #  forwarder = ZM::Device::Forwarder.new reactor, "tcp://192.168.0.100:5050", "tcp://192.168.0.100:5051"
    #
    #  # the +pub_handler+ internally calls "connect" to the incoming address given above
    #  pub1 = reactor.pub_socket pub_handler
    #  pub2 = reactor.pub_socket pub_handler
    #
    #  # the +sub_handler+ internally calls "connect" to the outgoing address given above
    #  subscriber = reactor.sub_socket sub_handler
    #
    class Forwarder

      class Handler
        attr_accessor :socket_out

        def initialize reactor, address, opts = {}
          @reactor = reactor
          @address = address
          @verbose = opts[:verbose] || false
          @opts = opts
          
          @messages = []
        end

        def on_attach socket
          socket.identity = "forwarder.#{Kernel.rand(999_999_999)}"
          set_options socket
          rc = socket.bind @address
          #FIXME: error handling!
          socket.subscribe_all if :sub == socket.kind
        end

        def on_writable socket
          @reactor.deregister_writable socket
        end

        def on_readable socket, messages
          messages.each { |msg| @reactor.log(:device, "[fwd] [#{msg.copy_out_string}]") } if @verbose

          if @socket_out
            rc = socket_out.send_messages messages
            messages.each { |message| message.close }
          end
        end
        
        def set_options socket
          socket.raw_socket.setsockopt ZMQ::HWM, (@opts[:hwm] || 1)
          socket.raw_socket.setsockopt ZMQ::LINGER, (@opts[:linger] || 0)
        end
        
      end # class Handler


      # Takes either a properly formatted string that can be converted into a ZM::Address
      # or takes a ZM::Address directly.
      #
      # Forwards all messages received by the +incoming+ address to the +outgoing+ address.
      #
      def initialize reactor, incoming, outgoing, opts = {:verbose => false}
        incoming = Address.from_string incoming if incoming.kind_of? String
        outgoing = Address.from_string outgoing if outgoing.kind_of? String

        # setup the handlers for processing messages
        @handler_in = Handler.new reactor, incoming, opts
        @handler_out = Handler.new reactor, outgoing, opts

        # create each socket and pass in the appropriate handler
        @incoming = reactor.sub_socket @handler_in
        @outgoing = reactor.pub_socket @handler_out

        # set each handler's outgoing socket
        @handler_in.socket_out = @outgoing
        @handler_out.socket_out = @incoming
      end
    end # class Forwarder

  end # module Device

end # module ZMQMachine

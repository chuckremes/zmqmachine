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
    #  config = ZM::Device::Configuration.new
    #  config.reactor = reactor
    #  config.incoming_endpoint = "tcp://192.168.0.100:5050"
    #  config.outgoing_endpoint = "tcp://192.168.0.100:5051"
    #  config.verbose = false
    #  config.linger = 10 # ms
    #  config.hwm = 0
    #  config.topic = '' # get everything
    #  forwarder = ZM::Device::Forwarder.new(config)
    #
    #  # the +pub_handler+ internally calls "connect" to the incoming address given above
    #  pub1 = reactor.pub_socket(pub_handler)
    #  pub2 = reactor.pub_socket(pub_handler)
    #
    #  # the +sub_handler+ internally calls "connect" to the outgoing address given above
    #  subscriber = reactor.sub_socket(sub_handler)
    #
    class Forwarder

      class Handler
        attr_accessor :socket_out

        def initialize(config, address)
          @reactor = config.reactor
          @address = address
          @verbose = config.verbose
          @config = config

          @messages = []
        end

        def on_attach(socket)
          set_options(socket)
          rc = socket.bind(@address)
          error_check(rc)

          error_check(socket.subscribe_all) if :sub == socket.kind
        end

        def on_writable(socket)
          @reactor.deregister_writable(socket)
        end

        def on_readable(socket, messages)
          messages.each { |msg| @reactor.log(:device, "[fwd] [#{msg.copy_out_string}]") } if @verbose

          if @socket_out
            rc = socket_out.send_messages(messages)
            error_check(rc)
            messages.each { |message| message.close }
          end
        end

        def on_readable_error(socket, return_code)
          @reactor.log(:error, "#{self.class}#on_readable_error, rc [#{return_code}], errno [#{ZMQ::Util.errno}], descr [#{ZMQ::Util.error_string}]")
        end

        if ZMQ::LibZMQ.version2?

          def set_options(socket)
            error_check(socket.raw_socket.setsockopt(ZMQ::HWM, @config.hwm))
            error_check(socket.raw_socket.setsockopt(ZMQ::LINGER, @config.linger))
          end

        elsif ZMQ::LibZMQ.version3?

          def set_options(socket)
            error_check(socket.raw_socket.setsockopt(ZMQ::SNDHWM, @config.hwm))
            error_check(socket.raw_socket.setsockopt(ZMQ::RCVHWM, @config.hwm))
            error_check(socket.raw_socket.setsockopt(ZMQ::LINGER, @config.linger))
          end

        end

        def error_check(rc)
          if ZMQ::Util.resultcode_ok?(rc)
            false
          else
            @reactor.log(:error, "Operation failed, errno [#{ZMQ::Util.errno}] description [#{ZMQ::Util.error_string}]")
            caller(1).each { |callstack| @reactor.log(:callstack, callstack) }
            true
          end
        end
      end # class Handler


      # Forwards all messages received by the +incoming+ address to the +outgoing+ address.
      #
      def initialize(config)
        @reactor = config.reactor
        incoming = Address.from_string(config.incoming_endpoint.to_s)
        outgoing = Address.from_string(config.outgoing_endpoint.to_s)

        # setup the handlers for processing messages
        @handler_in = Handler.new(config, incoming)
        @handler_out = Handler.new(config, outgoing)

        # create each socket and pass in the appropriate handler
        @incoming_sock = @reactor.sub_socket(@handler_in)
        @outgoing_sock = @reactor.pub_socket(@handler_out)

        # set each handler's outgoing socket
        @handler_in.socket_out = @outgoing_sock
        @handler_out.socket_out = @incoming_sock
      end
    end # class Forwarder

  end # module Device
end # module ZMQMachine

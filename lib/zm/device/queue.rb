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


    # Used in conjunction with REQ/REP sockets to load balance the requests and
    # replies over (potentially) multiple backends.
    #
    # The basic mechanics are that the program contains 1 (or more) clients that
    # talk to 1 (or more) backends that all perform the same work. Connecting to
    # an intermediate queue device allows for the client requests to be fair-balanced
    # among the available backend servers. The hidden identities passed along by
    # REQ/REP sockets are used by the queue device's internal XREQ/XREP sockets to
    # route the messages back to the appropriate client.
    #
    # Example:
    #
    #  # the queue creates sockets and binds to both given addresses; all messages get
    #  # routed between the two
    #  config = ZM::Device::Configuration.new
    #  config.reactor = reactor
    #  config.incoming_endpoint = "tcp://192.168.0.100:5050"
    #  config.outgoing_endpoint = "tcp://192.168.0.100:5051"
    #  config.verbose = false
    #  config.linger = 10 # ms
    #  config.hwm = 0
    #  queue = ZM::Device::Queue.new(config)
    #
    #  # the +client_handler+ internally calls "connect" to the incoming address given above
    #  client = reactor.req_socket(client_handler)
    #  client2 = reactor.req_socket(client_handler)
    #
    #  # the +server_handler+ internally calls "connect" to the outgoing address given above
    #  server = reactor.rep_socket(server_handler)
    #
    class Queue

      class Handler
        attr_accessor :socket_out

        def initialize(config, address, direction)
          @reactor = config.reactor
          @address = address
          @verbose = config.verbose
          @config = config
          @direction = direction
        end

        def on_attach(socket)
          set_options(socket)
          rc = socket.bind(@address)
          error_check(rc)
        end

        def on_writable(socket)
          @reactor.deregister_writable(socket)
        end

        def on_readable(socket, messages, envelope)
          all = envelope + messages

          if @verbose
            str = envelope.map { |msg| strhex(msg.copy_out_string) } + messages.map { |msg| msg.copy_out_string }
            str.unshift("[Q#{@direction}]")
            @reactor.log(:device, str.join("\n"))
          end

          if @socket_out
            # FIXME: need to be able to handle EAGAIN/failed send
            rc = socket_out.send_messages(all)
            
            if !ZMQ::Util.resultcode_ok?(rc)
              STDERR.print("error, #{self.class} failed to forward a message!\n")
              STDERR.print("error, #{self.class} errno [#{ZMQ::Util.errno}] [#{ZMQ::Util.error_string}]\n")
              STDERR.print(str.join("\n"))
            end
            
            all.each { |message| message.close }
          end
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

        # Helper method to create a hex string of a byte sequence.
        #
        def strhex(str)
          hex_chars = "0123456789ABCDEF"
          msg_size = str.size

          result = ""
          str.each_byte do |num|
            i1 = num >> 4
            i2 = num & 15
            result << hex_chars[i1]
            result << hex_chars[i2]
          end
          result
        end
      end # class Handler

      # Takes either a properly formatted string that can be converted into a ZM::Address
      # or takes a ZM::Address directly.
      #
      # Routes all messages received by either address to the other address.
      #
      def initialize(config)
        @reactor = config.reactor
        incoming = Address.from_string(config.incoming_endpoint.to_s)
        outgoing = Address.from_string(config.outgoing_endpoint.to_s)

        # setup the handlers for processing messages
        @handler_in = Handler.new(config, incoming, :in)
        @handler_out = Handler.new(config, outgoing, :out)

        # create each socket and pass in the appropriate handler
        @incoming_sock = @reactor.xrep_socket(@handler_in)
        @outgoing_sock = @reactor.xreq_socket(@handler_out)

        # set each handler's outgoing socket
        @handler_in.socket_out = @outgoing_sock
        @handler_out.socket_out = @incoming_sock
      end
    end # class Queue

  end # module Device
end # module ZMQMachine

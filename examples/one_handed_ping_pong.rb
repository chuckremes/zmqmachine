
require 'rubygems'
require 'ffi-rzmq'
require '../lib/zmqmachine'

# This example illustrates how a single handler can be used
# by multiple sockets.
#



Allowed_pongs = 100_000

class PingPongHandler
  attr_reader :sent_count, :received_count

  def initialize context
    @context = context
    @sent_count = 0
    @received_count = 0
  end

  def on_attach socket
    address = ZM::Address.new '127.0.0.1', 5555, :tcp

    case socket.kind
    when :reply
      rc = socket.bind address
    when :request
      rc = socket.connect address
      @context.register_readable socket
    end
  end

  def on_writable socket
    rc = socket.send_message_string "#{'a' * 2048}"
    @sent_count += 1

    # after sending the first message, deregister for future write events
    @context.deregister_writable socket
  end

  def on_readable socket, messages
    @received_count += 1

    if :reply == socket.kind
      #socket.send_message messages.first
      rc = socket.send_message_string messages.first.copy_out_string
    else
      socket.send_message messages.first
    end

    @sent_count += 1
    @context.next_tick { @context.stop } if @sent_count == Allowed_pongs
  end
end

handler = nil
# Run both handlers within the same reactor context
ctx1 = ZM::Reactor.new(:test).run do |context|
  handler = PingPongHandler.new context

  context.rep_socket handler

  context.req_socket handler

  start = Time.now
  timer = context.periodical_timer(2000) do
    now = Time.now
    puts "[#{now - start}] seconds have elapsed; it is now [#{now}]"
  end
end

ctx1.join 15_000
#puts "Started at [#{Time.now}]"
#puts "main thread will sleep [#{sleep_time}] seconds before aborting the context threads"
#sleep sleep_time
#
#ctx1.stop
#ctx2.stop
puts "received [#{handler.received_count}], sent [#{handler.sent_count}]"


require 'rubygems'
require 'ffi-rzmq'
require '../lib/zmqmachine'

# This example illustrates how to write a simple set of
# handlers for providing message ping-pong using
# a REQ/REP socket pair. All activity is asynchronous and
# relies on non-blocking I/O.


Allowed_pongs = 100_000


class PongHandler
  attr_reader :sent_count, :received_count

  def initialize context
    @context = context
    @sent_count = 0
    @received_count = 0
  end

  def on_attach socket
    address = ZM::Address.new '127.0.0.1', 5555, :tcp
    rc = socket.bind address
  end

  def on_readable socket, messages
    @received_count += 1
    socket.send_message messages.first
    @sent_count += 1

    @context.next_tick { @context.stop } if @sent_count == Allowed_pongs
  end
end

class PingHandler
  attr_reader :sent_count, :received_count

  def initialize context
    @context = context
    @sent_count = 0
    @received_count = 0
  end

  def on_attach socket
    @context.register_readable socket
    address = ZM::Address.new '127.0.0.1', 5555, :tcp
    rc = socket.connect address
    rc = socket.send_message_string "#{'a' * 2048}"
    @sent_count += 1
  end

  def on_readable socket, messages
    @received_count += 1
    rc = socket.send_message messages.first
    @sent_count += 1
  end
end

# Run both handlers within the same reactor context
ctx1 = ZM::Reactor.new(:test).run do |context|
  @pong_handler = PongHandler.new context
  context.rep_socket @pong_handler

  @ping_handler = PingHandler.new context
  context.req_socket @ping_handler

  start = Time.now
  timer = context.periodical_timer(2000) do
    now = Time.now
    puts "[#{now - start}] seconds have elapsed; it is now [#{now}]"
  end
end

# Or, run each handler in separate contexts each with its
# own thread.
#ctx2 = ZM::Reactor.new(:test).run do |context|
#  @ping_handler = PingHandler.new context
#  context.req_socket @ping_handler
#end


ctx1.join 15_000
#ctx2.join
puts "received [#{@pong_handler.received_count}], sent [#{@pong_handler.sent_count}]"

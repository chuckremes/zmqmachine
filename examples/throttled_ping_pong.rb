
require 'rubygems'
require 'ffi-rzmq'
require '../lib/zmqmachine'

# This example illustrates how to write a simple set of
# handlers for providing message ping-pong using
# a PAIR socket pair. All activity is asynchronous and
# relies on non-blocking I/O.
#
# The throttling aspect doesn't really kick in; need to
# ask the 0mq guys for clarity.

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
    pong socket, messages.first
  end

  def on_writable socket
    #puts "pong on_writable"
  end

  def pong socket, message
    socket.send_message message
    @sent_count += 1
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
    address = ZM::Address.new '127.0.0.1', 5555, :tcp
    rc = socket.connect address
  end

  def on_readable socket, messages
    @received_count += 1
  end

  def on_writable socket
    #puts "ping on_writable"
    ping socket
  end

  # send as fast as possible until we hit our high water
  # mark and get EAGAIN; then break
  def ping socket
    message = ZMQ::Message.new "#{'b' * 2048}"
    rc = socket.send_message message
    @sent_count += 1
  end
end



# Run both handlers within the same reactor context
ctx1 = ZM::Reactor.new.run do |context|
  @pong_handler = PongHandler.new context
  context.pair_socket @pong_handler

  # If you uncomment these 2 lines, comment out the
  # +ctx2+ block below.
  #  @ping_handler = PingHandler.new context
  #  context.pair_socket @ping_handler
end

# Or, run each handler in separate contexts each with its
# own thread.
ctx2 = ZM::Reactor.new.run do |context|
  @ping_handler = PingHandler.new context
  context.pair_socket @ping_handler
end

# let's see how many messages we can transfer in this many seconds
sleep_time = 5
puts "Started at [#{Time.now}]"
puts "main thread will sleep [#{sleep_time}] seconds before aborting the context threads"
sleep sleep_time

ctx1.stop
ctx2.stop
puts "received [#{@pong_handler.received_count}], sent [#{@ping_handler.sent_count}]"

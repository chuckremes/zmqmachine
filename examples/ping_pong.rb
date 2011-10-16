require 'rubygems'
require 'ffi-rzmq'

require File.expand_path(File.join(File.dirname(__FILE__), %w[.. lib zmqmachine]))

# This example illustrates how to write a simple set of
# handlers for providing message ping-pong using
# a REQ/REP socket pair. All activity is asynchronous and
# relies on non-blocking I/O.


Allowed_pongs = 100_000

def assert rc
  unless rc >= 0
    STDERR.puts "Failed with rc [#{rc}], errno [#{ZMQ::Util.errno}], msg [#{ZMQ::Util.error_string}]"
    STDERR.puts "0mq call failed! #{caller(1)}"
  end
end

class PongHandler
  attr_reader :sent_count, :received_count

  def initialize context
    @context = context
    @sent_count = 0
    @received_count = 0
  end

  def on_attach socket
    address = ZM::Address.new '127.0.0.1', 5555, :tcp
    assert(socket.bind(address))
  end

  def on_readable socket, messages
    @received_count += 1
    assert(socket.send_messages(messages))
    messages.each { |message| message.close }
    @sent_count += 1

    @context.next_tick { @context.stop } if @sent_count == Allowed_pongs
  end
  
  def on_writable socket
    puts "#{self.class} deregister writable"
    @context.deregister_writable socket
  end
  
  def on_readable_error socket, rc
    puts "ERROR: #{self.class} socket got rc [#{rc}]"
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
    @context.deregister_writable socket
    address = ZM::Address.new '127.0.0.1', 5555, :tcp
    assert(socket.connect(address))
    message = ZMQ::Message.new("#{'a' * 10}")
    assert(socket.send_message(message))
    message.close
    @sent_count += 1
  end

  def on_readable socket, messages
    @received_count += 1
    assert(socket.send_message(messages[-1]))
    messages.each { |message| message.close }
    @sent_count += 1
  end
  
  def on_writable socket
    puts "#{self.class} deregister writable"
    @context.deregister_writable socket
  end
  
  def on_readable_error socket, rc
    puts "ERROR: #{self.class} socket got rc [#{rc}]"
  end
end

def assert_not_nil obj
  puts "Object is nil allocated at #{caller(1)}" unless obj
end

# Run both handlers within the same reactor context
ctx1 = ZM::Reactor.new(:test).run do |context|
  @pong_handler = PongHandler.new context
  assert_not_nil(context.rep_socket(@pong_handler))

  @ping_handler = PingHandler.new context
  assert_not_nil(context.req_socket(@ping_handler))

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

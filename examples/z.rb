
require 'rubygems'
require 'ffi-rzmq'
require '../lib/zmqmachine'


# Shows how to publish from multiple PUB sockets to the same
# "bus" via a forwarder device.
#

class PublisherHandler
  attr_reader :sent_count

  def initialize context, port, topics
    @context = context
    @port = port
    @topics = topics
    @sent_count = 0
  end

  def on_attach socket
    address = ZM::Address.new '127.0.0.1', @port, :tcp
    rc = socket.connect address
  end

  def on_writable socket
    topic = @topics[rand(@topics.size)]
    symbol = topic.split('.').first

    if 'es' == symbol
      payload = "#{topic}|#{rand(1200) + 1}|#{rand(4400)}"
    else
      payload = "#{topic}|#{rand(300) + 1}|#{rand(8000)}"
    end

    message = ZMQ::Message.new payload
    socket.send_message message
    @sent_count += 1
  end
end

class SubscriberHandler
  attr_reader :received_count, :topics

  def initialize context, ports, topic = nil, sleep = false
    @context = context
    @received_count = 0
    @ports = ports
    (@topics ||= []) << topic.to_s
    @sleep = sleep
  end

  def on_attach socket
    @ports.each do |port|
      address = ZM::Address.new '127.0.0.1', port, :tcp
      rc = socket.connect address

      @topics.each do |topic|
        puts "subscribe to [#{topic}]"
        socket.subscribe topic
      end
    end
  end

  def on_readable socket, messages
    @received_count += 1
    sleep 0.01 if @sleep
  end
  
  def on_readable_error socket, return_code
    STDERR.puts "Failed, [#{ZMQ::Util.error_string}]"
    caller(1).each { |stack| STDERR.puts(stack) }
  end
end

sleep_time = 5


# Run the forwarder device in a separate context. *Could* be run from
# the same context as the publishers and subscribers too.
#
ctx1 = ZM::Reactor.new(:A).run do |context|
  incoming = ZM::Address.new '127.0.0.1', 5555, :tcp
  outgoing = "tcp://127.0.0.1:5556"

  forwarder = ZM::Device::Forwarder.new context, incoming, outgoing
  puts "forwarder started"
end

# Or, run each handler in separate contexts each with its
# own thread.
ctx2 = ZM::Reactor.new(:B).run do |context|
  # start the publishers and subscribers after a 1 sec delay; give time
  # to the forwarder device to start up and get ready
  context.oneshot_timer(1000) do
    @pub1_handler = PublisherHandler.new context, 5555, ['futures.us.es.m.10', 'futures.us.es.u.10']
    context.pub_socket @pub1_handler

    @pub2_handler = PublisherHandler.new context, 5555, ['futures.us.nq.m.10', 'futures.us.nq.u.10']
    context.pub_socket @pub2_handler
  end
end

ctx3 = ZM::Reactor.new(:B).run do |context|
  # start the publishers and subscribers after a 1 sec delay; give time
  # to the forwarder device to start up and get ready
  context.oneshot_timer(1000) do

    @sub1_handler = SubscriberHandler.new context, [5556]
    context.sub_socket @sub1_handler
  end
end

# let's see how many messages we can publish in this many seconds
puts "Started at [#{Time.now}]"
puts "main thread will sleep [#{sleep_time}] seconds before aborting the reactor context threads"
sleep sleep_time

puts "done sleeping"
puts "sent [#{@pub1_handler.sent_count}]"
puts "sent [#{@pub2_handler.sent_count}]"
puts "*               [#{@sub1_handler.received_count}]"
#puts "futures.us.ep.m [#{@sub2_handler.received_count}]"
#puts "futures.us.ep.u [#{@sub3_handler.received_count}]"
#puts "futures.us.nq.m [#{@sub4_handler.received_count}]"
#puts "futures.us.nq   [#{@sub5_handler.received_count}]"

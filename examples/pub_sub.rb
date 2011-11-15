
require 'rubygems'
require 'ffi-rzmq'
require '../lib/zmqmachine'


# Shows how to use a PUB socket to send messages in a fanout
# manner. A set of SUB sockets subscribe using different topic
# matches.
#
# The example also shows how to communicate between multiple
# reactors by running some operations in different contexts.
# Modify which lines are commented in/out within each context
# to see how performance changes in different scenarios.
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
    rc = socket.bind address
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
end


# Mix and match the handlers amongst the 5 reactors below. Make sure that a publisher
# handler is only getting instantiated and run in one reactor at a time. The subscriber
# handlers can be instantiated multiple times in each reactor if you so choose.

configuration = ZM::Configuration.new do
  name 'publisher reactor'
  poll_interval 3
  exception_handler Proc.new { |exc| raise(exc) }
end

# Run all handlers within the same reactor context
ctx1 = ZM::Reactor.new(configuration).run do |context|
  @pub1_handler = PublisherHandler.new context, 5555, ['futures.us.es.m.10', 'futures.us.es.u.10']
  context.pub_socket @pub1_handler

  #  @pub2_handler = PublisherHandler.new context, 5556, ['futures.us.nq.m.10', 'futures.us.nq.u.10']
  #  context.pub_socket @pub2_handler
  #
  #  @sub1_handler = SubscriberHandler.new context, [5555, 5556]
  #  context.sub_socket @sub1_handler
  #
  #  @sub2_handler = SubscriberHandler.new context, [5555], 'futures.us.es.m'
  #  context.sub_socket @sub2_handler
  #
  #  @sub3_handler = SubscriberHandler.new context, [5555], 'futures.us.es.u'
  #  context.sub_socket @sub3_handler
  #
  #  @sub4_handler = SubscriberHandler.new context, [5556], 'futures.us.nq.m'
  #  context.sub_socket @sub4_handler
  #
  #  @sub5_handler = SubscriberHandler.new context, [5555, 5556], 'futures.us.'
  #  context.sub_socket @sub5_handler
end

# Or, run each handler in separate contexts each with its
# own thread.
ctx2 = ZM::Reactor.new.run do |context|
  #  @pub1_handler = PublisherHandler.new context, 5555, ['futures.us.es.m.10', 'futures.us.es.u.10']
  #  context.pub_socket @pub1_handler

  @pub2_handler = PublisherHandler.new context, 5556, ['futures.us.nq.m.10', 'futures.us.nq.u.10']
  context.pub_socket @pub2_handler

  #  @sub1_handler = SubscriberHandler.new context, [5555, 5556]
  #  context.sub_socket @sub1_handler
  #
  #  @sub2_handler = SubscriberHandler.new context, [5555], 'futures.us.es.m'
  #  context.sub_socket @sub2_handler
  #
  #  @sub3_handler = SubscriberHandler.new context, [5555], 'futures.us.es.u'
  #  context.sub_socket @sub3_handler
  #
  #  @sub4_handler = SubscriberHandler.new context, [5556], 'futures.us.nq.m'
  #  context.sub_socket @sub4_handler
  #
  #  @sub5_handler = SubscriberHandler.new context, [5555, 5556], 'futures.us.'
  #  context.sub_socket @sub5_handler
end

ctx3 = ZM::Reactor.new.run do |context|
  #  @pub1_handler = PublisherHandler.new context, 5555, ['futures.us.es.m.10', 'futures.us.es.u.10']
  #  context.pub_socket @pub1_handler
  #
  #  @pub2_handler = PublisherHandler.new context, 5556, ['futures.us.nq.m.10', 'futures.us.nq.u.10']
  #  context.pub_socket @pub2_handler
  #
  @sub1_handler = SubscriberHandler.new context, [5555, 5556]
  context.sub_socket @sub1_handler

  @sub2_handler = SubscriberHandler.new context, [5555], 'futures.us.es.m'
  context.sub_socket @sub2_handler

  @sub3_handler = SubscriberHandler.new context, [5555], 'futures.us.es.u'
  context.sub_socket @sub3_handler

  @sub4_handler = SubscriberHandler.new context, [5556], 'futures.us.nq.m'
  context.sub_socket @sub4_handler

  #  @sub5_handler = SubscriberHandler.new context, [5555, 5556], 'futures.us.'
  #  context.sub_socket @sub5_handler
end

ctx4 = ZM::Reactor.new.run do |context|
  #  @pub1_handler = PublisherHandler.new context, 5555, ['futures.us.es.m.10', 'futures.us.es.u.10']
  #  context.pub_socket @pub1_handler
  #
  #  @pub2_handler = PublisherHandler.new context, 5556, ['futures.us.nq.m.10', 'futures.us.nq.u.10']
  #  context.pub_socket @pub2_handler
  #
  #  @sub1_handler = SubscriberHandler.new context, [5555, 5556]
  #  context.sub_socket @sub1_handler
  #
  #  @sub2_handler = SubscriberHandler.new context, [5555], 'futures.us.es.m'
  #  context.sub_socket @sub2_handler
  #
  #  @sub3_handler = SubscriberHandler.new context, [5555], 'futures.us.es.u'
  #  context.sub_socket @sub3_handler
  #
  #  @sub4_handler = SubscriberHandler.new context, [5556], 'futures.us.nq.m'
  #  context.sub_socket @sub4_handler

  @sub5_handler = SubscriberHandler.new context, [5555, 5556], 'futures.us.'
  context.sub_socket @sub5_handler
end

# let's see how many messages we can publish in this many seconds
sleep_time = 5
puts "Started at [#{Time.now}]"
puts "main thread will sleep [#{sleep_time}] seconds before aborting the reactor context threads"
sleep sleep_time

# Exit each reactor after the sleep time
ctx1.stop
ctx2.stop
ctx3.stop
ctx4.stop

puts "sent [#{@pub1_handler.sent_count}]"
puts "sent [#{@pub2_handler.sent_count}]"
puts "*               [#{@sub1_handler.received_count}]"
puts "futures.us.ep.m [#{@sub2_handler.received_count}]"
puts "futures.us.ep.u [#{@sub3_handler.received_count}]"
puts "futures.us.nq.m [#{@sub4_handler.received_count}]"
puts "futures.us.nq   [#{@sub5_handler.received_count}]"

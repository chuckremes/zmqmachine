
require 'rubygems'
require 'ffi-rzmq'
require '../lib/zmqmachine'


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
    messages.each { |message| message.close }
  end
end

sleep_time = 900


# Or, run each handler in separate contexts each with its
# own thread.
ctx2 = ZM::Reactor.new(:B).run do |context|

  setup_sub = Proc.new do
    handler = SubscriberHandler.new context, [5556]
    socket = context.sub_socket handler
    socket.raw_socket.setsockopt ZMQ::LINGER, 0

    context.oneshot_timer((rand(3) + 1) * 1_000) do
      context.close_socket socket
      puts "closing socket after [#{handler.received_count}] packets, reopening...."
      setup_sub.call
    end
  end
  
  setup_sub.call

end

# let's see how many messages we can publish in this many seconds
puts "Started at [#{Time.now}]"
puts "main thread will sleep [#{sleep_time}] seconds before aborting the reactor context threads"
sleep sleep_time

puts "done sleeping"
puts "sent [#{@pub1_handler.sent_count}]"
#puts "sent [#{@pub2_handler.sent_count}]"
puts "*               [#{@sub1_handler.received_count}]"
puts "futures.us.ep.m [#{@sub2_handler.received_count}]"
puts "futures.us.ep.u [#{@sub3_handler.received_count}]"
puts "futures.us.nq.m [#{@sub4_handler.received_count}]"
puts "futures.us.nq   [#{@sub5_handler.received_count}]"

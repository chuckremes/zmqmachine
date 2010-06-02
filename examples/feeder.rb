
require 'rubygems'
require 'ffi-rzmq'
require 'json'
require '../lib/zmqmachine'

# This example shows how to use REQ/REP sockets to do a simple kind of
# asynchronous remote method call with callback (RPC). The remote call
# is taking a Proc/block which will be used to process the incoming
# data. When the remote call completes, everything is unwoud.


# sleep_time is part of the outer-scope so it is visible inside
# the handlers. This number controls how many seconds each handler
# waits before stopping their context.
sleep_time = 20
client_address = ZMQ::Address.new '127.0.0.1', 5555, :tcp
server_address = ZMQ::Address.new '127.0.0.1', 6555, :tcp
DB_host = '192.168.0.104'


class BarSubHandler
  def initialize context, address, topic, process
    @context = context
    @address = address
    @topic = topic
    @process = process
    @received_count = 0
    @expected_count = 0
    @state = :incomplete
  end

  def on_attach socket
    @socket = socket
    @socket.bind @address
    @socket.subscribe @topic
  end

  def on_readable socket, message
    bars = decode strip_topic(message.copy_out_string)
    @received_count += @process.call(bars)

    @context.close_socket(@socket) if complete?
  end

  def on_writable(socket); end

  def request_total=(val)
    @expected_count = val
  end

  def strip_topic payload
    payload.split('|').last
  end

  def complete?
    @state = @expected_count > 0 && @received_count >= @expected_count ? :complete : :incomplete
  end


  private

  def decode string
    JSON.parse string
  end
end

class BarRequestClient
  def initialize context, address
    @context = context
    @address = address
    @received_count = 0
  end

  def on_attach socket
    @socket = socket
    rc = socket.connect @address
  end

  def on_readable socket, message
    reply = decode message.copy_out_string
    @bar_total = reply['total_count']
    puts "reply #{reply.inspect}"
  end

  def get symbol, duration, start_time, finish_time, &blk
    sub_address = ZMQ::Address.new @address.host, 5556, @address.transport
    topic = "#{symbol}.#{duration}"

    @sub_socket = @context.sub_socket(BarSubHandler.new(sub_address, topic, blk))

    req = {'symbol' => symbol, 'duration' => duration, 'start_time' => start_time,
    'finish_time' => finish_time, 'reply_to' => sub_address.to_s}

    @socket.send_message_string encode(req)
  end

  def on_writable socket
    puts "#{self.class.name} on_writable, should never be called"
  end

  private

  def decode string
    JSON.parse string
  end
  
  def encode obj
    JSON.generate obj
  end
end

class BarPubHandler
  attr_reader :total_count
  def initialize request
    @request = request
    @address_string = request['reply_to']
    @topic = "#{request['symbol']}.#{request['duration']}"
    @total_count = 0
    @market_data = Mongo::Connection.new(DB_host).db("meta_market_data").collection("bars")
    continuation_map = ContinuationMap.new({:host => DB_host}).find_by_base_symbol(request['symbol'], :host => DB_host)
    @ranges = continuation_map['selector']['ranges'] if continuation_map
  end

  def on_attach socket
    @state = if open_cursor
      @socket = socket
      @socket.connect @address_string
      :fulfilling
    else
      :complete
    end
  end

  def on_writable socket
    unless complete?
      if @cursor.has_next?
        @total_count += 1
        socket.send_string encode(@cursor.next_document, @topic)
      else
        # this cursor is exhausted so try and open one for the
        # next available range, otherwise complete
        @state = open_cursor ? :fulfilling : :complete
      end
    end
  end

  def complete?
    :complete == @state
  end


  private

  # Grab the contract from the next continuation range and select all of the data that
  # is available up to its expiration OR the end of the request period.
  #
  def open_cursor
    unless @ranges.empty?
      range = @ranges.shift
      finish = [@request['finish'], range['finish_date']].min

      # a nice side effect of cursors is that they are *always* returned even when no
      # data matches the query
      @cursor = @market_data.find({'_id.cid' => range['contract_id'], '_id.ts' => {"$gte" => @request['start'], "$lt" => finish}},
      {:sort => [['_id.ts', Mongo::ASCENDING]]})
      true
    else
      false
    end
  end

  def encode obj, topic = nil
    preamble = "#{topic}|" if topic
    "#{preamble}#{JSON.generate(obj)}"
  end
end

class BarRequestServer
  def initialize context, address
    @context = context
    @address = address
    @sent_count = 0
  end

  def on_attach socket
    @socket = socket
    rc = socket.bind @address
  end

  def on_readable socket, message
    request = decode message.copy_out_string
    puts "#{self.class.name}: query #{request.inspect}"
    @pub_handler = BarPubHandler.new request
    @pub_socket = @context.pub_socket @pub_handler

    schedule_completion_check
  end

  def schedule_completion_check
    # check every 20 ms for completion
    # if complete, reply with total document count
    # else reschedule for another check
    @context.oneshot_timer 20, self.method(:completion_check)
  end

  def completion_check
    if @pub_handler.complete?
      # send reply
      reply = encode 'total_count' => @pub_handler.total_count
      @socket.send_message_string reply
      @pub_socket.close
      @pub_handler = nil # allow for GC
    else
      # reschedule
      schedule_completion_check
    end
  end

  def on_writable socket
    puts "requesthandler on_writable, should never be called"
  end


  private

  def decode string
    JSON.parse string
  end

  def encode obj
    JSON.generate obj
  end
end


# Run both handlers within the same reactor context
ctx1 = ZM::Reactor.new(:test).run do |context|
  @request_server = BarRequestServer.new context, server_address
  context.rep_socket @request_server

  @request_client = BarRequestClient.new context, server_address
  context.req_socket @request_client
  
  @request_client.get('F.US.EP', 60, 1072936800, 1104559200) do |meta_bar|
    puts "metabar #{meta_bar.inspect}"
  end

#  @fulfillment_handler = BarFulfillmentHandler.new context
#  context.req_socket @fulfillment_handler
end

# Or, run each handler in separate contexts each with its
# own thread.
#ctx2 = ZM::Reactor.new(:test).run do |context|
#  @ping_handler = PingHandler.new context
#  context.req_socket @ping_handler
#end

puts "Started at [#{Time.now}]"
puts "main thread will sleep [#{sleep_time}] seconds before aborting the context threads"
sleep sleep_time

ctx1.stop
#ctx2.stop
puts "received [#{@pong_handler.received_count}], sent [#{@pong_handler.sent_count}]"

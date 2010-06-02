
require 'rubygems'
require 'ffi-rzmq'
require 'json'
require '../lib/zmqmachine'

# This example shows how to pair up REQ/REP sockets with PUB/SUB
# sockets for doing an RPC-style request with an out-of-band
# response. The RPC reply contains information about the out-of-
# band data so the servers know that the transfer was complete.
#


server_address = ZM::Address.new '127.0.0.1', 6555, :tcp


class FTPDataClient
  include ZM::Deferrable
  
  def initialize context, address, topic, process
    @context = context
    @address = address
    @topic = topic
    @process = process
    @received_count = 0
    @expected_count = -1
    
    callback do
      puts "FTPDataClient#callback fired, received all file chunks"
      @context.next_tick { @context.stop }
    end
  end

  def on_attach socket
    @socket = socket
    @socket.bind @address
    @socket.subscribe @topic
  end

  def on_readable socket, message
      obj = decode strip_topic(message.copy_out_string)
      puts "#{self.class.name}#on_readable: process obj #{obj.inspect}"
      @received_count += @process.call(obj)
      succeed if complete?
  end

  def on_writable(socket); puts "#{self.class.name}#on_writable, should never be called"; end
  
  def should_expect count
    puts "#{self.class.name}#should_expect, set to expect [#{count}], already received [#{@received_count}]"
    @expected_count = count
    succeed if complete?
  end


  private
  
  def strip_topic payload
    payload.split('|').last
  end

  def complete?
    @expected_count > 0 && @expected_count == @received_count
  end

  def decode string
    JSON.parse string
  end
end

class FTPControlClient
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
    puts "#{self.class.name}#on_readable: reply from FTPDataServer #{reply.inspect}"

    @data_client.should_expect reply['total_chunks']
  end

  def get filename, &blk
    sub_address = ZM::Address.new @address.host, 5556, @address.transport
    topic = "file.#{filename}|"

    @data_client = FTPDataClient.new @context, sub_address, topic, blk
    @sub_socket = @context.sub_socket @data_client
    
    req = {'filename' => filename, 'reply_to' => sub_address.to_s}

    puts "#{self.class.name}#get: send request for the file chunks to be published"
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

class FTPDataServer
  include ZM::Deferrable

  attr_reader :total_count

  def initialize request
    @request = request
    @address_string = request['reply_to']
    @topic = "file.#{request['filename']}|"
    @total_count = 0
  end

  def on_attach socket
    if open_file
      @socket = socket
      @socket.connect @address_string
    else
      puts "#{self.class.name}#on_attach: @total_count is 0"
      succeed @total_count
    end
  end

  def on_writable socket
    if more_file_data?
      @total_count += 1
      obj = encode(next_file_chunk)
      puts "#{self.class.name}#on_writable: send chunk [#{@total_count}], obj #{obj.inspect}"
      socket.send_message_string obj
    else
      puts "#{self.class.name}#on_writable: done [#{@total_count}]"
      succeed @total_count
    end
  end


  private

  def open_file
    @chunks = rand(5) + 5
    @chunks > 0
  end

  def more_file_data?
    @chunks > 0
  end

  def next_file_chunk
    @chunks -= 1
    chunk = rand(999_999_999) + 1_000_000_000
    {'chunk' => chunk}
  end

  def encode obj
    "#{@topic}#{JSON.generate(obj)}"
  end
end

class FTPControlServer
  def initialize context, address
    @context = context
    @address = address
  end

  def on_attach socket
    @socket = socket
    rc = socket.bind @address
  end

  def on_readable socket, message
    request = decode message.copy_out_string
    puts "#{self.class.name}: query #{request.inspect}"
    @pub_handler = FTPDataServer.new request
    @pub_socket = @context.pub_socket @pub_handler

    @pub_handler.callback do |total_chunks|
      puts "FTPDataServer#callback fired, sent all file chunks"

      reply = encode 'total_chunks' => total_chunks
      socket.send_message_string reply

      # clean up after ourselves
      @context.close_socket @pub_socket
      @pub_handler = nil
    end
  end

  def on_writable socket
    puts "#{self.class.name}#on_writable ERROR, should never be called"
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
  
  @request_server = FTPControlServer.new context, server_address
  context.rep_socket @request_server

  @request_client = FTPControlClient.new context, server_address
  context.req_socket @request_client

  @request_client.get('fakeo') do |file_chunk|
    puts "block: file chunk #{file_chunk.inspect}"
    
    # the number of chunks processed in this block; this return
    # value is used by FTPDataClient#on_readable for tallying
    # the total number of processed chunks.
    1 
  end

end


ctx1.join

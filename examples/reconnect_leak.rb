
require 'rubygems'
require 'ffi-rzmq'
require 'zmqmachine'


# Shows how to publish from multiple PUB sockets to the same
# "bus" via a forwarder device.
#
Thread.abort_on_exception = true

class PublisherHandler

  def initialize reactor, port
    @reactor = reactor
    @port = port

    #@topic = "any old string of bytes"
    @data = "b"#{}"#{'a' * 32767}" # a string of 'a' characters 32k long
  end

  def on_attach socket
    #address = ZM::Address.new '127.0.0.1', @port, :tcp
    address = ZM::Address.new 'first_inproc', nil, :inproc
    #socket.raw_socket.setsockopt ZMQ::HWM, 1
    socket.raw_socket.setsockopt ZMQ::LINGER, 0

    rc = socket.connect address

    @reactor.deregister_writable socket

    # set a timer to publish a message every 1ms
    @reactor.periodical_timer(1) do
      #topic_message = ZMQ::Message.new @topic
      data_message = ZMQ::Message.new @data
      #socket.send_messages [topic_message, data_message]
      puts "publishing msg..."
      socket.send_messages [data_message]
    end
  end

  def on_writable(s) nil; end
end



reactors = []

# Or, run each handler in separate reactors each with its
# own thread.
reactors.push(
ZM::Reactor.new(:Publisher, 1).run do |reactor|
  mainclosure = Proc.new do
    handler = PublisherHandler.new reactor, 5555
    publisher_sock = reactor.pub_socket handler
    
    reactor.oneshot_timer(1000) do
      puts "closing socket"
      reactor.close_socket publisher_sock
      handler = nil
      mainclosure.call
    end
  end
  
  mainclosure.call
end
)


sleep # blocks forever

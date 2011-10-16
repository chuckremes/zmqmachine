
require 'rubygems'
require 'ffi-rzmq'
require 'zmqmachine'


reactor = ZM::Reactor.new(:A).run do |reactor|
  incoming = ZM::Address.new '127.0.0.1', 5555, :tcp
  outgoing = ZM::Address.new '127.0.0.1', 5556, :tcp

  forwarder = ZM::Device::Forwarder.new(reactor, incoming, outgoing, {:hwm => 1, :verbose => false})
end

sleep
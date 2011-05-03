$: << "." # added for ruby 1.9.2 compatibilty; it doesn't include the current directory on the load path anymore

require File.join(File.dirname(__FILE__), %w[spec_helper])

module ZM
  
  describe Reactor do
    
    
    context "when closing sockets" do
      let(:reactor) { Reactor.new(:test) }
      
      it "should return false when the given socket is nil" do
        reactor.close_socket(nil).should be_false
      end
      
      it "should return true when the given socket is successfully closed and deleted" do
        sock = reactor.req_socket(FakeHandler.new)
        
        reactor.close_socket(sock).should be_true
      end
    end
  end # describe Reactor
  
end # module ZM


module ZMQMachine
  module Device
    ZMQMachine::ConfigClassMaker.create_class('Configuration', 
    %w( reactor incoming_endpoint outgoing_endpoint topic hwm linger verbose ), 
    ZMQMachine::Configuration, 
    ZMQMachine::Device)
    
    class Configuration
      def initialize(&blk)
        # set defaults
        self.reactor = nil
        self.incoming_endpoint = nil
        self.outgoing_endpoint = nil
        self.topic = ''
        self.hwm = 1
        self.linger = 0
        self.verbose = false

        instance_eval(&blk) if block_given?
      end

    end
  end
end


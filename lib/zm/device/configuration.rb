
module ZMQMachine
  module Device
    ZMQMachine::ConfigClassMaker.create_class('Configuration', 
    %w( reactor incoming_endpoint outgoing_endpoint topic hwm linger verbose ), 
    ZMQMachine::Configuration, 
    ZMQMachine::Device)
    
    class Configuration
      
      def initialize(&blk)
        instance_eval(&blk) if block_given?

        # set defaults
        self.verbose ||= false
        self.hwm ||= 1
        self.linger ||= 0
        self.topic ||= ''
      end

    end
  end
end


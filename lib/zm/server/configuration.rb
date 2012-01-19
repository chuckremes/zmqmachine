
module ZMQMachine
  module Server
    ZMQMachine::ConfigClassMaker.create_class('Configuration', 
    %w( on_read bind connect endpoint topic hwm linger extra reactor ), 
    ZMQMachine::Configuration, 
    ZMQMachine::Server)
    
    
    class Configuration
      def initialize(&blk)
        self.on_read = nil
        self.bind = false
        self.connect = false
        self.endpoint = nil
        self.topic = ''
        self.hwm = 0
        self.linger = 0
        self.extra = nil
        self.reactor = nil

        instance_eval(&blk) if block_given?
      end
    end

  end
end

#module ZMQMachine
#
#  module Server
#
#    class Configuration
#      Fields = %w( on_read bind connect endpoint topic hwm linger extra reactor name context log_endpoint exception_handler )
#      
#      # Creates a Configuration object from another object that conforms
#      # to the Configuration protocol.
#      #
#      def self.create_from(other_config)
#        config = new
#        Fields.each do |name|
#          config.send("#{name}", other_config.send(name.to_sym)) if config.respond_to?(name.to_sym)
#        end
#        config
#      end
#      
#      def initialize(&blk)
#        instance_eval(&blk) if block_given?
#      end
#
#      Fields.each do |name|
#        code = <<-code
#        def #{ name } (value = nil)
#          if value
#            @#{name} = value
#          else
#            @#{name}
#          end
#        end
#        
#        def #{ name }=(value)
#          @#{name} = value
#        end
#        code
#
#        class_eval code
#      end
#    end # class Configuration
#    
#  end # Server
#end # ZMQMachine

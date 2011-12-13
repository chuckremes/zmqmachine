

module ZMQMachine
  module ConfigClassMaker
    module MethodMaker

      # Helper to create some accessor methods. We have a standard one where it returns
      # the value with no arg, or sets the value with an arg. Then we create a second
      # method with the explicit '=' on it to allow directly setting the value.
      #
      # This let's us do nice things like eval a block and set the instance vars.
      # e.g.
      #  SomeClass.new do
      #    field1 'set to this string'
      #  end
      #
      # or
      #
      #  some_class = SomeClass.new
      #  some_class.field1 = 'set to this string'
      #  puts some_class.field1 # => set to this string
      #
      # or
      #
      #  some_class = SomeClass.new
      #  some_class.field1('set to this string')
      #  puts some_class.field1 # => set to this string
      #
      def self.create_accessors(mod, fields)
        fields.each do |field_name|
          code = <<-code
          def #{ field_name } (value = nil)
            if value
              @#{field_name} = value
            else
              @#{field_name}
            end
          end

          def #{ field_name }=(value)
            @#{field_name} = value
          end
          code

          mod.class_eval code
        end
      end

    end # module MethodMaker

    # Dynamically generates Configuration classes. It can also create subclasses.
    # Allows us to easily build subclasses of Configuration within the library. This
    # functionality is *also* provided for users of this library to create their
    # own Configuration classes when writing client/server programs. All of the
    # inheritance is taken care of.
    #
    # +klass_name+ - should usually be 'Configuration'
    # +fields+ - an array of strings corresponding to the accessor names
    # +parent+ - the parent of this subclass (Object at the top level)
    # +mod+ - the module under which this subclass should be placed
    #
    # module ZMQMachine
    #   ZMQMachine::ConfigClassMaker.create_class('Configuration', %w( one two three), Object, ZMQMachine)
    # end
    #
    # OR for a subclass
    #
    # module ZMQMachine
    #  module Server
    #    ZMQMachine::ConfigClassMaker.create_class('Configuration', %w( one two three), ZMQMachine::Configuration, ZMQMachine::Server)
    #  end
    # end
    #
    def self.create_class(klass_name, fields, parent, mod)
      # the "here doc" usage here confuses the syntax beautifier so the indentation
      # is wrong
      klass = <<-KLASS
      #{klass_name} = Class.new(#{parent}) do

      Fields = #{fields.inspect}

      # Creates a Configuration object from another object that conforms
      # to the Configuration protocol.
      #
      def self.create_from(other_config, debug = false)
        config = new
        
        # only iterate over fields that +other_config+ has defined
        other_config.class.fields.each do |name|
          puts "config.send(" + name + ")" if debug
          config.send(name, other_config.send(name.to_sym)) if config.respond_to?(name.to_sym)
        end
        config        
      end
      
      def self.fields
        if defined?(super)
          super + Fields
        else
          Fields
        end
      end

      def initialize(&blk)
        instance_eval(&blk) if block_given?
      end
      
      def inspect
        self.class.fields.map { |field| [field, send(field)] }.join(', ')
      end

      ZMQMachine::ConfigClassMaker::MethodMaker.create_accessors(self, Fields)
    end
    KLASS

    mod.module_eval(klass)

    # Error out if there are any duplicate field names defined
    new_klass = mod.const_get(klass_name.to_sym)
    dupes = new_klass.fields.size - new_klass.fields.uniq.size
    
    unless dupes.zero?
      error_message = "Found [#{dupes}] duplicate configuration fields defined for class [#{new_klass}] with parent class [#{parent}]\n"
      error_message += "#{new_klass}.fields :\n"
      error_message += new_klass.fields.inspect
      error_message += "#{parent}.fields :\n"
      error_message += parent.fields.inspect
      raise(error_message)
    end
  end
end
end

module ZMQMachine

  ZMQMachine::ConfigClassMaker.create_class('Configuration', %w( name poll_interval context log_endpoint exception_handler ), Object, ZMQMachine)
end # ZMQMachine



# TEST
if $0 == __FILE__
ZMQMachine::ConfigClassMaker.create_class('Configuration', %w( name context log_endpoint exception_handler ), Object, ZMQMachine)

p (ZMQMachine::Configuration.methods - Object.methods).sort
puts "\n\n"
p (ZMQMachine::Configuration.new.methods - Object.new.methods).sort

module ZMQMachine
  module Server
    ZMQMachine::ConfigClassMaker.create_class('Configuration', %w( bind connect endpoint ), ZMQMachine::Configuration, ZMQMachine::Server)
  end
end

puts "\n\n"
p (ZMQMachine::Server::Configuration.new.methods - Object.new.methods).sort
end


%w( configuration forwarder queue ).each do |rb_file|
  require File.join(File.dirname(__FILE__), 'devices', rb_file)
end

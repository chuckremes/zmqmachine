
%w( configuration forwarder queue ).each do |rb_file|
  require File.join(File.dirname(__FILE__), 'device', rb_file)
end

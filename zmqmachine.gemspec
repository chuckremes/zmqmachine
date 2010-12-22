# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{zmqmachine}
  s.version = "0.4.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Chuck Remes"]
  s.date = %q{2010-12-22}
  s.description = %q{ZMQMachine is another Ruby implementation of the reactor pattern but this
time using 0mq sockets rather than POSIX sockets.

Unlike the great Eventmachine ruby project and the Python Twisted
project which work with POSIX sockets, ZMQMachine is inherently threaded. The
0mq sockets backing the reactor use a thread pool for performing
their work so already it is different from most other reactors. Also, a
single program may create multiple reactor instances which runs in
its own thread. All activity within the reactor is single-threaded
and asynchronous.

It is possible to extend the 0mq library to "poll" normal file
descriptors. This isn't on my roadmap but patches are accepted.}
  s.email = %q{cremes@mac.com}
  s.extra_rdoc_files = ["History.txt", "README.rdoc", "version.txt"]
  s.files = [".bnsignore", "History.txt", "README.rdoc", "Rakefile", "examples/fake_ftp.rb", "examples/one_handed_ping_pong.rb", "examples/ping_pong.rb", "examples/pub_sub.rb", "examples/pubsub_forwarder.rb", "examples/throttled_ping_pong.rb", "lib/zm/address.rb", "lib/zm/deferrable.rb", "lib/zm/devices.rb", "lib/zm/devices/forwarder.rb", "lib/zm/devices/queue.rb", "lib/zm/exceptions.rb", "lib/zm/message.rb", "lib/zm/reactor.rb", "lib/zm/sockets.rb", "lib/zm/sockets/base.rb", "lib/zm/sockets/pair.rb", "lib/zm/sockets/pub.rb", "lib/zm/sockets/rep.rb", "lib/zm/sockets/req.rb", "lib/zm/sockets/sub.rb", "lib/zm/sockets/xrep.rb", "lib/zm/sockets/xreq.rb", "lib/zm/timers.rb", "lib/zmqmachine.rb", "spec/spec_helper.rb", "spec/zmqmachine_spec.rb", "version.txt", "zmqmachine.gemspec"]
  s.homepage = %q{http://github.com/chuckremes/zmqmachine}
  s.rdoc_options = ["--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{zmqmachine}
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{ZMQMachine is another Ruby implementation of the reactor pattern but this time using 0mq sockets rather than POSIX sockets.}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<ffi-rzmq>, [">= 0.7.0"])
      s.add_development_dependency(%q<bones>, [">= 3.5.4"])
    else
      s.add_dependency(%q<ffi-rzmq>, [">= 0.7.0"])
      s.add_dependency(%q<bones>, [">= 3.5.4"])
    end
  else
    s.add_dependency(%q<ffi-rzmq>, [">= 0.7.0"])
    s.add_dependency(%q<bones>, [">= 3.5.4"])
  end
end

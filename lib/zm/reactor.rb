#--
#
# Author:: Chuck Remes
# Homepage::  http://github.com/chuckremes/zmqmachine
# Date:: 20100602
#
#----------------------------------------------------------------------------
#
# Copyright (C) 2010 by Chuck Remes. All Rights Reserved.
# Email: cremes at mac dot com
#
# (The MIT License)
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#---------------------------------------------------------------------------
#
#

module ZMQMachine

  class Reactor
    attr_reader :name

    # +poll_interval+ is the number of milliseconds to block while
    # waiting for new 0mq socket events; default is 0
    #
    def initialize name, poll_interval = 0
      @name = name
      @running = false
      @thread = nil
      @poll_interval = determine_interval poll_interval
      @timers = ZMQMachine::Timers.new

      @proc_queue = []
      @proc_queue_mutex = Mutex.new

      # could raise if it fails
      @context = ZMQ::Context.new 1
      @poller = ZMQ::Poller.new
      @sockets = []
      @raw_to_socket = {}
      Thread.abort_on_exception = true
    end

    # Returns true when the reactor is running OR while it is in the
    # midst of a shutdown request.
    #
    # Returns false when the reactor thread does not exist.
    #
    def running?() @running; end

    # The main entry point for all new reactor contexts. This proc
    # or block given to this method is evaluated *once* before
    # entering the reactor loop. This evaluation generally sets up
    # sockets and timers that will do the real work once the loop
    # is executed.
    #
    def run blk = nil, &block
      blk ||= block
      @running, @stopping = true, false

      @thread = Thread.new do
        blk.call self if blk

        while !@stopping && @running do
          run_once
        end

        cleanup
      end
      self
    end

    # Marks the reactor as eligible for termination. Then waits for the
    # reactor thread to exit via #join (no timeout).
    #
    # The reactor is not forcibly terminated if it is currently blocked
    # by some long-running operation. Use #kill to forcibly terminate
    # the reactor.
    #
    def stop
      # wait until the thread loops around again and exits on its own
      @stopping = true
      join
    end

    # Join on the thread running this reactor instance. Default behavior
    # is to wait indefinitely for the thread to exit.
    #
    # Pass an optional +delay+ value measured in milliseconds; the
    # thread will be stopped if it hasn't exited by the end of +delay+
    # milliseconds.
    #
    # Returns immediately when the thread has already exited.
    #
    def join delay = nil
      # don't allow the thread to try and join itself and only worry about
      # joining for live threads
      if @thread.alive? && @thread != Thread.current
        if delay
          # convert to seconds to meet the argument expectations of Thread#join
          seconds = delay / 1000.0
          @thread.join seconds
        else
          @thread.join
        end
      end
    end

    # Kills the running reactor instance by terminating its thread.
    #
    # After the thread exits, the reactor attempts to clean up after itself
    # and kill any pending I/O.
    #
    def kill
      @stopping = true
      @thread.kill
      cleanup
    end

    # Schedules a proc or block to execute on the next trip through the
    # reactor loop.
    #
    # This method is thread-safe.
    #
    def next_tick blk = nil, &block
      blk ||= block
      @proc_queue_mutex.synchronize do
        @proc_queue << blk
      end
    end

    # Removes the given +sock+ socket from the reactor context. It is deregistered
    # for new events and closed. Any queued messages are silently dropped.
    #
    def close_socket sock
      delete_socket sock
      sock.raw_socket.close
    end

    # Creates a REQ socket and attaches +handler_instance+ to the
    # resulting socket. Should only be paired with one other
    # #rep_socket instance.
    #
    # +handler_instance+ must implement the #on_writable and
    # #on_writable_error methods. The reactor will call those methods
    # based upon new events.
    #
    # All handlers must implement the #on_attach method.
    #
    def req_socket handler_instance
      sock = ZMQMachine::Socket::Req.new @context, handler_instance
      save_socket sock
      sock
    end

    # Creates a REP socket and attaches +handler_instance+ to the
    # resulting socket. Should only be paired with one other
    # #req_socket instance.
    #
    # +handler_instance+ must implement the #on_readable and
    # #on_readable_error methods. The reactor will call those methods
    # based upon new events.
    #
    # All handlers must implement the #on_attach method.
    #
    def rep_socket handler_instance
      sock = ZMQMachine::Socket::Rep.new @context, handler_instance
      save_socket sock
      sock
    end

    # Creates a XREQ socket and attaches +handler_instance+ to the
    # resulting socket. Should only be paired with one other
    # #rep_socket instance.
    #
    # +handler_instance+ must implement the #on_readable,
    # #on_readable_error, #on_writable and #on_writable_error
    # methods. The reactor will call those methods
    # based upon new events.
    #
    # All handlers must implement the #on_attach method.
    #
    def xreq_socket handler_instance
      sock = ZMQMachine::Socket::XReq.new @context, handler_instance
      save_socket sock
      sock
    end

    # Creates a XREP socket and attaches +handler_instance+ to the
    # resulting socket. Should only be paired with one other
    # #req_socket instance.
    #
    # +handler_instance+ must implement the #on_readable,
    # #on_readable_error, #on_writable and #on_writable_error
    # methods. The reactor will call those methods
    # based upon new events.
    #
    # All handlers must implement the #on_attach method.
    #
    def xrep_socket handler_instance
      sock = ZMQMachine::Socket::XRep.new @context, handler_instance
      save_socket sock
      sock
    end

    # Creates a PAIR socket and attaches +handler_instance+ to the
    # resulting socket. Works only with other #pair_socket instances
    # in the same or other reactor instance.
    #
    # +handler_instance+ must implement the #on_readable and
    # #on_readable_error methods. Each handler must also implement
    # the #on_writable and #on_writable_error methods.
    # The reactor will call those methods
    # based upon new events.
    #
    # All handlers must implement the #on_attach method.
    #
    def pair_socket handler_instance
      sock = ZMQMachine::Socket::Pair.new @context, handler_instance
      save_socket sock
      sock
    end

    # Creates a PUB socket and attaches +handler_instance+ to the
    # resulting socket. Usually paired with one or more
    # #sub_socket instances in the same or other reactor instance.
    #
    # +handler_instance+ must implement the #on_writable and
    # #on_writable_error methods. The reactor will call those methods
    # based upon new events. This socket type can *only* write; it
    # can never receive/read messages.
    #
    # All handlers must implement the #on_attach method.
    #
    def pub_socket handler_instance
      sock = ZMQMachine::Socket::Pub.new @context, handler_instance
      save_socket sock
      sock
    end

    # Creates a SUB socket and attaches +handler_instance+ to the
    # resulting socket. Usually paired with one or more
    #  #pub_socket in the same or different reactor context.
    #
    # +handler_instance+ must implement the #on_readable and
    # #on_readable_error methods. The reactor will call those methods
    # based upon new events. This socket type can *only* read; it
    # can never write/send messages.
    #
    # All handlers must implement the #on_attach method.
    #
    def sub_socket handler_instance
      sock = ZMQMachine::Socket::Sub.new @context, handler_instance
      save_socket sock
      sock
    end

    # Registers the +sock+ for POLLOUT events that will cause the
    # reactor to call the handler's on_writable method.
    #
    def register_writable sock
      @poller.register_writable sock.raw_socket
    end

    # Deregisters the +sock+ for POLLOUT. The handler will no longer
    # receive calls to on_writable.
    #
    def deregister_writable sock
      @poller.deregister_writable sock.raw_socket
    end

    # Registers the +sock+ for POLLIN events that will cause the
    # reactor to call the handler's on_readable method.
    #
    def register_readable sock
      @poller.register_readable sock.raw_socket
    end

    # Deregisters the +sock+ for POLLIN events. The handler will no longer
    # receive calls to on_readable.
    #
    def deregister_readable sock
      @poller.deregister_readable sock.raw_socket
    end

    # Creates a timer that will fire a single time. Expects either a
    # +timer_proc+ proc or a block, otherwise no timer is created.
    #
    # +delay+ is measured in milliseconds (1 second equals 1000
    # milliseconds)
    #
    def oneshot_timer delay, timer_proc = nil, &blk
      blk ||= timer_proc
      @timers.add_oneshot delay, blk
    end

    # Creates a timer that will fire every +delay+ milliseconds until
    # it is explicitly cancelled. Expects either a +timer_proc+ proc
    # or a block, otherwise no timer is created.
    #
    # +delay+ is measured in milliseconds (1 second equals 1000
    # milliseconds)
    #
    def periodical_timer delay, timer_proc = nil, &blk
      blk ||= timer_proc
      @timers.add_periodical delay, blk
    end

    # Cancels an existing timer if it hasn't already fired.
    #
    # Returns true if cancelled, false if otherwise.
    #
    def cancel_timer timer
      @timers.cancel timer
    end
    
    # Asks all timers to reschedule themselves starting from Timers.now.
    # Typically called when the underlying time source for the ZM::Timers
    # class has been replaced; existing timers may not fire as expected, so
    # we ask them to reset themselves.
    #
    def reschedule_timers
      @timers.reschedule
    end


    private

    def run_once
      run_procs
      run_timers
      poll
    end

    # Close each open socket and terminate the reactor context; this will
    # release the native memory backing each of these objects
    def cleanup
      # work on a dup since #close_socket deletes from @sockets
      @sockets.dup.each { |sock| close_socket sock }
      @context.terminate
      @running = false
    end

    def run_timers
      @timers.fire_expired
    end

    # work on a copy of the queue; some procs may reschedule themselves to
    # run again immediately, so by using a copy we make them wait until the next
    # loop
    def run_procs
      work = nil
      @proc_queue_mutex.synchronize do
        work, @proc_queue = @proc_queue, []
      end

      until work.empty? do
        work.pop.call
      end
    end

    def poll
      @poller.poll @poll_interval

      @poller.readables.each { |sock| @raw_to_socket[sock].resume_read }
      @poller.writables.each { |sock| @raw_to_socket[sock].resume_write }
    end

    def save_socket sock
      @poller.register sock.raw_socket, sock.poll_options
      @sockets << sock
      @raw_to_socket[sock.raw_socket] = sock
    end

    def delete_socket sock
      @poller.delete sock.raw_socket
      @sockets.delete sock
      @raw_to_socket.delete sock.raw_socket
    end


    # Internally converts the number to microseconds
    def determine_interval interval
      # set a lower bound of 100 usec so we don't burn up the CPU
      interval <= 0 ? 100 : (interval * 1000).to_i
    end

  end # class Reactor


  # Not implemented. Just a (broken) thought experiment at the moment.
  #
  class SyncReactor

    def initialize name
      @klass_path = ZMQMachine::Sync
      @poll_interval = 10
      @active = true
      super name
    end

    def run blk = nil, &block
      blk ||= block
      @running = true

      @thread = Thread.new do
        @fiber = Fiber.new { |context| blk.call context }
        func = Proc.new { |context| @fiber.resume context }

        run_once func
        while @running do
          run_once
        end

        cleanup
      end

      self
    end

    def deactivate() @active = false; end

    def active?() @active; end

    def while_active? &blk
      begin
        while @active do
          yield
        end
      rescue => e
        p e
      end

      @running = false
    end


    private

    def poll
      @poller.poll @poll_interval

      @poller.writables.each { |sock| sock.resume }
      @poller.readables.each { |sock| sock.resume }
    end
  end # class SyncReactor

end # module ZMQMachine

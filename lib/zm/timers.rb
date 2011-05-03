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

  # Manages the addition and cancellation of all timers. Each #Reactor
  # maintains its own set of timers; the timer belongs to the
  # reactor context.
  #
  # This should never be instantiated directly
  # by user code. A timer must be known to the #Reactor in which it
  # is running, so use the #Reactor#oneshot_timer and
  # #Reactor#periodical_timer convenience methods. It ensures that
  # new timers are installed in the correct #Reactor.
  #
  class Timers
    def initialize
      @timers = []
    end

    def list
      @timers
    end

    # Adds a non-periodical, one-shot timer in order of
    # first-to-fire to last-to-fire.
    #
    # Returns nil unless a +timer_proc+ or +blk+ are
    # provided. There is no point to an empty timer that
    # does nothing when fired.
    #
    def add_oneshot delay, timer_proc = nil, &blk
      blk ||= timer_proc
      return nil unless blk

      timer = Timer.new self, delay, false, blk
      add timer
      timer
    end

    # Adds a periodical timer in order of
    # first-to-fire to last-to-fire.
    #
    # Returns nil unless a +timer_proc+ or +blk+ are
    # provided. There is no point to an empty timer that
    # does nothing when fired.
    #
    def add_periodical delay, timer_proc = nil, &blk
      blk ||= timer_proc
      return nil unless blk

      timer = Timer.new self, delay, true, blk
      add timer
      timer
    end

    # Cancel the +timer+.
    #
    # Returns +true+ when cancellation succeeds.
    # Returns +false+ when it fails to find the
    # given +timer+.
    #
    def cancel timer
      i = index timer

      # when #index doesn't find a match, it returns an index 1 past
      # the end, so check for that
      if i < @timers.size && timer == @timers.at(i)
        @timers.delete_at(i) ? true : false
      else
        # slow branch; necessary since the #index operation works 
        # solely from the timer.fire_time attribute. There
        # could be multiple timers scheduled to fire at the
        # same time so the equivalence test above could fail
        # on the first index returned, so fallback to this
        # slower method
        size = @timers.size
        @timers.delete_if { |t| t == timer }
        
        # true when the array has shrunk, false otherwise
        @timers.size != size
      end
    end

    # A convenience method that loops through all known timers
    # and fires all of the expired timers.
    #
    #--
    # Internally the list is sorted whenever a timer is added or
    # deleted. It stops processing this list when the next timer
    # is not yet expired; it knows all subsequent timers are not
    # expired too.
    #
    # timers should be sorted by expiration time
    # NOTE: was using #delete_if here, but it does *not* delete any
    # items when the break executes before iterating through the entire
    # set; that's unacceptable so I save each timer for deletion and
    # do that in a separate loop
    #
    # Additionally, some timers may execute code paths that cancel other
    # timers. If those timers are deleted while we are still iterating
    # over them, the behavior is undefined (each runtime can handle it
    # differently). To avoid that issue, we determine if they are expired
    # and save them off for final processing outside of the loop. Any
    # firing timer that deletes another timer will be safe.
    #
    def fire_expired
      # all time is expected as milliseconds
      now = Timers.now
      runnables, periodicals, expired_count = [], [], 0

      # defer firing the timer until after this loop so we can clean it up first
      @timers.each do |timer|
        break unless timer.expired?(now)
        runnables << timer
        periodicals << timer if timer.periodical?
        expired_count += 1
      end

      remove expired_count
      runnables.each { |timer| timer.fire }
      renew periodicals
    end

    # Runs through all timers and asks each one to reschedule itself
    # from Timers.now + whatever delay was originally recorded.
    #
    def reschedule
      timers = @timers.dup
      @timers.clear

      timers.each do |timer|
        timer.reschedule
        add timer
      end
    end

    # Returns the current time using the following algo:
    #
    #  (Time.now.to_f * 1000).to_i
    #
    # Added as a class method so that it can be overridden by a user
    # who wants to provide their own time source. For example, a user
    # could use a third-party gem that provides a better performing
    # time source.
    #
    def self.now
      (Time.now.to_f * 1000).to_i
    end

    # Convert Timers.now to a number usable by the Time class.
    #
    def self.now_converted
      now / 1000.0
    end


    private

    # inserts in order using a binary search (O(nlog n)) to find the 
    # index to insert; this scales nicely for situations where there
    # are many thousands thousands of timers
    def add timer
      i = index timer
      @timers.insert(i, timer)
    end

    # Original Ruby source Posted by Sergey Chernov (sergeych) on 2010-05-13 20:23
    # http://www.ruby-forum.com/topic/134477
    #
    # binary search; assumes underlying array is already sorted
    def index value
      l, r = 0, @timers.size - 1

      while l <= r
        m = (r + l) / 2
        if value < @timers.at(m)
          r = m - 1
        else
          l = m + 1
        end
      end
      l
    end

    def remove expired_count
      # the timers are ordered, so we can just shift them off the front
      # of the array; this is *orders of magnitude* faster than #delete_at
      # with a (reversed) array of indexes
      expired_count.times { @timers.shift }
    end

    def renew timers
      # reinstate the periodicals; necessary to do in two steps
      # since changing the timer.fire_time inside the loop (in parent) would
      # not retain proper ordering in the sorted list; re-adding it
      # ensures the timers are in sorted order
      timers.each { |timer| add timer }
    end
  end # class Timers


  # Used to track the specific expiration time and execution
  # code for each timer.
  #
  # This should never be instantiated directly
  # by user code. A timer must be known to the #Reactor in which it
  # is running, so use the #Reactor#oneshot_timer and
  # #Reactor#periodical_timer convenience methods. It ensures that
  # new timers are installed in the correct #Reactor.
  #
  class Timer
    include Comparable

    attr_reader :fire_time, :timer_proc

    # +delay+ is in milliseconds
    #
    def initialize timers, delay, periodical, timer_proc = nil, &blk
      @timers = timers
      @delay = delay.to_i
      @periodical = periodical
      @timer_proc = timer_proc || blk
      schedule_firing_time
    end

    # Executes the callback.
    #
    # Returns +true+ when the timer is a one-shot;
    # Returns +false+ when the timer is periodical and has rescheduled
    # itself.
    #
    def fire
      @timer_proc.call

      schedule_firing_time if @periodical
    end

    # Cancels this timer from firing.
    #
    def cancel
      @timers.cancel self
    end

    def <=>(other)
      @fire_time <=> other.fire_time
    end
    
    def ==(other)
      # need a more specific equivalence test since multiple timers could be
      # scheduled to go off at exactly the same time
      @fire_time == other.fire_time &&
      @timer_proc == other.timer_proc &&
      periodical? == other.periodical?
    end

    # True when the timer should be fired; false otherwise.
    #
    def expired? time
      time ||= Timers.now
      time >= @fire_time
    end

    # True when this is a periodical timer; false otherwise.
    #
    def periodical?
      @periodical
    end

    def reschedule
      schedule_firing_time
    end
    
    def to_s
      ftime = Time.at(@fire_time / 1000)
      fdelay = @fire_time - Timers.now
      name = @timer_proc.respond_to?(:name) ? @timer_proc.name : @timer_proc.to_s
      
      "[delay [#{@delay}], periodical? [#{@periodical}], fire_time [#{ftime}] fire_delay_ms [#{fdelay}]] proc [#{name}]"
    end
    
    def inspect; to_s; end


    private

    # calculate the time when this should fire; note that
    # the use of #now grabs the current time and adds the
    # delay on top. When this timer is late in firing (due
    # to a blocking operation or other blocker preventing
    # this from running on time) then we will see the next
    # scheduled firing time slowly drift.
    # e.g. Fire at time 10 + delay 5 = 15
    # timer late, fires at 17
    # next timer to fire at, 17 + delay 5 = 22
    # had it not been late, it would fire at 20
    def schedule_firing_time
      @initiated = Timers.now

      @fire_time = @initiated + @delay
    end

  end # class Timer

end # module ZMQMachine

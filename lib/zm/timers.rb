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
      @timers = SortedSet.new
    end
    
    def list
      @timers.to_a
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
      @timers.add timer
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
      @timers.add timer
      timer
    end

    # Cancel the +timer+.
    #
    # Returns +true+ when cancellation succeeds.
    # Returns +false+ when it fails to find the
    # given +timer+.
    #
    def cancel timer
      @timers.delete(timer) ? true : false
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
    def fire_expired
      # all time is expected as milliseconds
      now = Timers.now
      save = []
      delete = []

      # timers should be sorted by expiration time
      # NOTE: was using #delete_if here, but it does *not* delete any
      # items when the break executes before iterating through the entire
      # set; that's unacceptable so I save each timer for deletion and
      # do that in a separate loop
      @timers.each do |timer|
        break unless timer.expired?(now)
        timer.fire
        save << timer if timer.periodical?
        delete << timer
      end

      delete.each { |timer| @timers.delete timer }

      # reinstate the periodicals; necessary to do in two steps
      # since changing the timer.fire_time inside the loop would
      # not retain proper ordering in the sorted set; re-adding it
      # ensures the timers are in sorted order
      save.each { |timer| @timers.add timer }
    end

    # Runs through all timers and asks each one to reschedule itself
    # from Timers.now + whatever delay was originally recorded.
    #
    def reschedule
      timers = @timers.dup
      @timers.clear

      timers.each do |timer|
        timer.reschedule
        @timers.add timer
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

    # +time+ is in milliseconds
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
      self.fire_time <=> other.fire_time
    end

    # True when the timer should be fired; false otherwise.
    #
    def expired? time
      time ||= now
      time > @fire_time
    end

    # True when this is a periodical timer; false otherwise.
    #
    def periodical?
      @periodical
    end

    def reschedule
      schedule_firing_time
    end


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

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

  #FIXME: needs to handle ipc and inproc transports better, e.g.
  # there is no port component to either one.
  #
  class Address
    attr_reader :host, :port, :transport

    # +type+ : :tcp, :pgm or :inprocess
    def initialize host, port, type = :tcp
      @host = host
      @port = port
      @transport = determine_type type
    end

    def to_s
      "#{@transport}://#{@host}:#{@port}"
    end


    # Converts strings with the format "type://host:port" into
    # an Address instance.
    #
    def self.from_string string
      #FIXME: needs error checking and ability to handle inproc/ipc types
      #
      # should also return nil or some other error indication when parsing fails
      split = string.split(':')
      type = split[0]
      port = split[2]
      host = split[1].sub('//', '')

      Address.new host, port, type.to_sym
    end

    private

    def determine_type type
      case type
      when :inprocess
        :inproc
      when :tcp, :pgm
        type
      else
        raise UnknownAddressError, "Unknown address transport type [#{type}]; must be :tcp, :pgm, or :inprocess"
      end
    end

  end # class Address
end # module ZMQMachine

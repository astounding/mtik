############################################################################
## A Ruby library implementing the Ruby MikroTik API
############################################################################
## Author::    Aaron D. Gifford - http://www.aarongifford.com/
## Copyright:: Copyright (c) 2009-2010, InfoWest, Inc.
## License::   BSD license
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 1. Redistributions of source code must retain the above copyright
##    notice, the above list of authors and contributors, this list of
##    conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
## 3. Neither the name of the author(s) or copyright holder(s) nor the
##    names of any contributors may be used to endorse or promote products
##    derived from this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S), AUTHOR(S) AND
## CONTRIBUTORS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
## INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
## AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
## IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), AUTHOR(S), OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## DCONSEQUENTIAL AMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
## THE POSSIBILITY OF SUCH DAMAGE.
############################################################################

## A MikroTik API request object is stored as an array of MikroTik
## API-style words, the first word being the command, subsequent words
## (if any) are command arguments.  Each request will automatically
## have a unique tag generated (so any +.tag=value+ arguments will be
## ignored). A request is incomplete until the final +!done+ response
## sentence has been received.
class MTik::Request < Array
  @@tagspace = 0  ## Used to keep all tags unique.

  ## Create a new MTik::Request.
  ## +await_completion+ :: A boolean parameter indicating when callback(s)
  ##                    should be called.  A value of _true_ will result
  ##                    in callback(s) only being called once, when the
  ##                    final +!done+ response is received.  A value of
  ##                    _false_ means callback(s) will be called _each_
  ##                    time a response sentence is received.
  ## +command+ ::       The MikroTik API command to execute (a String).
  ##                    Examples:
  ##                      * +"/interface/getall"+
  ##                      * +"/ip/route/add"+
  ## +args+ ::          Zero or more String arguments for the command,
  ##                    already encoded in +"=key=value"+, +".id=value"+
  ##                    or +"?query"+ API format.
  ## +callback+::       A Proc or code block may be passed which will
  ##                    be called with two arguments:
  ##                     1. this MTik::Request object; and
  ##                     2. the most recently received response sentence.
  ##                    When or how often callbacks are called depends on
  ##                    whether the +await_completion+ parameter is _true_
  ##                    or _false_ (see above).
  def initialize(await_completion, command, *args, &callback)
    @reply            = MTik::Reply.new
    @command          = command
    @await_completion = await_completion
    @complete         = false

    args.flatten!
    @callbacks = Array.new
    if block_given?
      @callbacks.push(callback)
    elsif args.length > 0 && args[args.length-1].is_a?(Proc)
      @callbacks.push(args.pop)
    end

    super(&nil)
    ## Add command to the request sentence list:
    self.push(command)

    ## Add all arguments to the request sentence list:
    self.addargs(*args)

    ## Append a unique tag for the request:
    @tag = @@tagspace.to_s
    @@tagspace += 1
    self.push(".tag=#{@tag}")
  end

  ## Add one or more callback Procs and/or a code block
  ## to the callback(s) that will be executed upon reply
  ## (either complete or partial, depending on the
  ## _await_completion_ setting)
  def append_callback(*callbacks, &callback)
    callbacks.flatten!
    callbacks.each do |cb|
      @callbacks.push(cb)
    end
    if block_given?
      @callbacks.push(callback)
    end
  end

  ## Append one or more arguments to the not-yet-sent request
  def addargs(*args)
    ## Add all additional arguments to the request sentence list:
    args.each do |arg|
      if arg.is_a?(Hash)
        ## Prepend argument keys that don't begin with the API-
        ## command-specific parameter character '.', nor the
        ## normal parameter charactre '=', nor the query character
        ## '?' with the ordinary parameter character '=':
        arg.each do |key, value|
          key = '=' + key unless /^[\?\=\.]/.match(key)
          addarg(key + '=' + value)
        end
      else
        addarg(arg)
      end
    end
  end

  ## Append a single argument to the not-yet-sent request
  def addarg(arg)
    unless /^\.tag=/.match(arg)
      self.push(arg)
    end
  end

  ## Return the boolean completion status of the request,
  ## _true_ if complete, _false_ if not-yet-complete.
  def done?
    return @complete
  end

  attr_reader  :command, :tag, :await_completion, :reply

  ## Execute all callbacks, passing _sentence_ along as
  ## the second parameter to each callback.
  def callback(sentence)
    case @callbacks.length
    when 0
      return nil
    when 1
      return @callbacks[0].call(self, sentence)
    else
      result = Array.new
      @callbacks.each do |cb|
        result.push(cb.call(self, sentence))
      end
      return result
    end
  end

  ## Utility method for packing an unsigned integer as
  ## a binary byte string of variable length
  def self.bytepack(num)
    s = String.new
    if RUBY_VERSIION >= '1.9.0'
      s.force_encoding(Encoding::BINARY)
    end
    x = num < 0 ? -num : num  ## Treat as unsigned
    while x > 0
      s += (x & 0xff).chr
      x >>= 8
    end
    return s
  end

  ## Another utility method to encode a byte string as a
  ## valid API _"word"_
  def self.to_tikword(str)
    str = str.dup
    if RUBY_VERSION >= '1.9.0'
      str.force_encoding(Encoding::BINARY)
    end
    if str.length < 0x80
      return str.length.chr + str
    elsif str.length < 0x4000
      return bytepack(str.length | 0x8000) + str
    elsif str.length < 0x200000
      return bytepack(str.length | 0xc00000) + str
    elsif str.length < 0x10000000
      return bytepack(str.length | 0xe0000000) + str
    elsif str.length < 0x0100000000
      return 0xf0.chr + bytepack(str.length) + str
    else
      raise RuntimeError.new(
        "String is too long to be encoded for " +
        "the MikroTik API using a 4-byte length!"
      )
    end
  end

  ## Encode this request as a binary byte string ready for transmission
  ## to a MikroTik device
  def request
    ## Encode the request for sending to the device:
    return self.map {|w| MTik::Request::to_tikword(w)}.join + 0x00.chr
  end

  ## Method the internal parser calls to flag this reply as completed
  ## upon receipt of a +!done+ reply sentence.
  def done!
    return @complete = true
  end
end


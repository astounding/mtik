############################################################################
## A Ruby library implementing the Ruby MikroTik API
############################################################################
## Author::    Aaron D. Gifford - http://www.aarongifford.com/
## Copyright:: Copyright (c) 2009-2011, InfoWest, Inc.
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
# encoding: ASCII-8BIT

## The MTik::Connection class is the workhorse where most stuff gets done.
## Create an instance of this object to connect to a MikroTik device via
## the API and execute commands (requests) and receive responses (replies).
class MTik::Connection
  require 'socket'
  require 'digest/md5'
  require 'openssl'

  ## Initialize/construct the new _MTik_ object.  One or more
  ## key/value pair style arguments must be specified. The one
  ## required argument is the host or IP of the device to connect
  ## to.
  ## +host+:: This is the only _required_ argument. Example:
  ##          <i> :host => "rb411.example.org" </i>
  ## +ssl+::  Use SSL to encrypt communications
  ## +port+:: Override the default API port (8728/8729)
  ## +user+:: Override the default API username ('admin')
  ## +pass+:: Override the default API password (blank)
  ## +conn_timeout+:: Override the default connection
  ##                  timeout (60 seconds)
  ## +cmd_timeout+::  Override the default command timeout
  ##                  (60 seconds) -- the number of seconds
  ##                  to wait for additional API input.
  ## +unencrypted_plaintext+::  Attempt to use the 6.43+ login API even without SSL
  def initialize(args)
    @sock                  = nil
    @ssl_sock              = nil
    @requests              = Hash.new
    @use_ssl               = args[:ssl] || MTik::USE_SSL
    @unencrypted_plaintext = args[:unecrypted_plaintext]
    @host                  = args[:host]
    @port                  = args[:port] || (@use_ssl ? MTik::PORT_SSL : MTik::PORT)
    @user                  = args[:user] || MTik::USER
    @pass                  = args[:pass] || MTik::PASS
    @conn_timeout          = args[:conn_timeout] || MTik::CONN_TIMEOUT
    @cmd_timeout           = args[:cmd_timeout]  || MTik::CMD_TIMEOUT
    @data                  = ''
    @parsing               = false  ## Recursion flag
    @os_version            = nil

    ## Initiate connection and immediately login to device:
    login
  end

  ## Return the number of currently outstanding requests
  def outstanding
    return @requests.length
  end
  attr_reader :requests, :host, :port, :user, :pass, :conn_timeout, :cmd_timeout,
              :os_version

  ## Internal utility function:
  ## Sugar-coat ["0deadf0015"].pack('H*') so one can just do
  ## "0deadf0015".hex2bin instead.  Prepend a '0' if the hex
  ## string doesn't have an even number of digits.
  def hex2bin(str)
    return str.length % 2 == 0 ?
      [str].pack('H*') :
      ['0'+str].pack('H*')
  end

  ## Connect and login to the device using the API
  def login
    connect
    unless connected?
      raise MTik::Error.new("Login failed: Unable to connect to device.")
    end

    # Try using the the post-6.43 login API; on older routers this still initiates
    # a regular challenge-response cycle.
    if @use_ssl || @unencrypted_plaintext
      warn("SENDING PLAINTEXT PASSWORD OVER UNENCRYPTED CONNECTION") unless @use_ssl
      reply = get_reply('/login',["=name=#{@user}","=password=#{@pass}"])
      if reply.length == 1 && reply[0].length == 2 && reply[0].key?('!done')
        v_6_43_login_successful = true
      end
    else
      ## Just send first /login command to obtain the challenge, if not using SSL
      reply = get_reply('/login')
    end

    unless v_6_43_login_successful
      ## Make sure the reply has the info we expect for challenge-response authentication:
      if reply.length != 1 || reply[0].length != 3 || !reply[0].key?('ret')
        raise MTik::Error.new("Login failed: unexpected reply to login attempt.")
      end

      ## Grab the challenge from first (only) sentence in the reply:
      challenge = hex2bin(reply[0]['ret'])

      ## Generate reply MD5 hash and convert binary hash to hex string:
      response  = Digest::MD5.hexdigest(0.chr + @pass + challenge)

      ## Send second /login command with our response:
      reply = get_reply('/login', '=name=' + @user, '=response=00' + response)
      if reply[0].key?('!trap')
        raise MTik::Error.new("Login failed: " + (reply[0].key?('message') ? reply[0]['message'] : 'Unknown error.'))
      end
      unless reply.length == 1 && reply[0].length == 2 && reply[0].key?('!done')
        @sock.close
        @sock = nil
        raise MTik::Error.new('Login failed: Unknown response to login.')
      end
    end

    ## Request the RouterOS version of the device as different versions
    ## sometimes use slightly different command parameters:
    reply = get_reply('/system/resource/getall')
    if reply.first.key?('!re') && reply.first['version']
      @os_version = reply.first['version']
    end
  end

  ## Connect to the device
  def connect
    return unless @sock.nil?
    ## TODO: Perhaps catch more errors
    begin
      addr = Socket.getaddrinfo(@host, nil)
      @sock = Socket.new(Socket.const_get(addr[0][0]), Socket::SOCK_STREAM, 0)

      begin
        @sock.connect_nonblock(Socket.pack_sockaddr_in(@port, addr[0][3]))
      rescue Errno::EINPROGRESS
        ready = IO.select([@sock], [@sock], [], @conn_timeout)
        if ready
          @sock
        else
          raise Errno::ETIMEDOUT
      end
    end

    connect_ssl(@sock) if @use_ssl

    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ENETUNREACH,
           Errno::EHOSTUNREACH => e
      @sock = nil
      raise e ## Re-raise the exception
    end
  end

  def connect_ssl(sock)
    ssl_context = OpenSSL::SSL::SSLContext.new()
    ssl_context.ciphers = ['HIGH']
    ssl_socket = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
    ssl_socket.sync_close = true
    unless ssl_socket.connect
      raise MTik::Error.new("Cannot establish SSL connection.")
    end
    @ssl_sock = ssl_socket
  end

  ## Wait for and read exactly one sentence, regardless of content:
  def get_sentence
    ## TODO: Implement timeouts, detect disconnection, maybe do auto-reconnect
    if @sock.nil?
      raise MTik::Error.new("Cannot retrieve reply sentence--not connected.")
    end
    sentence = Hash.new
    oldlen = -1
    while true ## read-data loop
      if @data.length == oldlen
        sleep(1)  ## Wait for some more data
      else
        while true  ## word parsing loop
          bytes, word = get_tikword(@data)
          @data[0, bytes] = ''
          if word.nil?
            break
          end
          if word.length == 0
            ## Received END-OF-SENTENCE
            if sentence.length == 0
              raise MTik::Error.new("Received END-OF-SENTENCE from device with no sentence data.")
            end
            ## Debugging or verbose, show the received sentence:
            if MTik::debug || MTik::verbose
              sentence.each do |k, v|
                if v.nil?
                  STDERR.print ">>> '#{k}' (#{k.length})\n"
                else
                  STDERR.print ">>> '#{k}=#{v}' (#{k.length+v.length+1})\n"
                end
              end
              STDERR.print ">>> END-OF SENTENCE\n\n"
            end
            if sentence.key?('!fatal')
              ## Fatal error (or '/quit'):
              close  ## Assume disconnection
            end
            ## Finished. Return the sentence:
            return sentence
          else
            ## Add word to sentence
            m = /^=?([^=]+)=(.*)$/.match(word)
            unless m.nil?
              sentence[m[1]] = m[2]
            else
              sentence[word] = nil
            end
          end
        end  ## word parsing loop
      end
      oldlen = @data.length
      ## Read some more data IF any is available:
      sock = @ssl_sock || @sock
      sel = IO.select([sock],nil,[sock], @cmd_timeout)
      if sel.nil?
        raise MTik::TimeoutError.new(
          "Time-out while awaiting data with #{outstanding} pending " +
          "requests: '" + @requests.values.map{|req| req.command}.join("' ,'") + "'"
        )
      end
      if sel[0].length == 1
        @data += recv(8192)
      elsif sel[2].length == 1
        raise MTik::Error.new(
          "I/O (select) error while awaiting data with #{outstanding} pending " +
          "requests: '" + @requests.values.map{|req| req.command}.join("' ,'") + "'"
        )
      end
    end  ## read-data loop
  end

  ## Keep reading replies until ALL outstanding requests have completed
  def wait_all
    while outstanding > 0
      wait_for_reply
    end
  end

  ## Keep reading replies until a SPECIFIC command has completed.
  def wait_for_request(req)
    while !req.done?
      wait_for_reply
    end
  end

  ## Read one or more reply sentences.
  ## TODO: Implement timeouts, detect disconnection, maybe do auto-reconnect
  def wait_for_reply
    ## Sanity check:
    if @data.length > 0 && !@parsing
      raise MTik::Error.new("An unexpected #{@data.length} bytes were found from a previous reply. API utility may be buggy.\n")
    end
    if @requests.length < 1
      raise MTik::Error.new("Cannot retrieve reply--No request was made.")
    end

    ## SENTENCE READING LOOP:
    oldparsing = @parsing
    @parsing = true
    begin
      ## Fetch a sentence:
      sentence = get_sentence  ## This call must be ATOMIC or re-entrant safety fails

      ## Check for '!fatal' before checking for a tag--'!fatal'
      ## is never(???) tagged:
      if sentence.key?('!fatal')
        ## FATAL ERROR has occured! (Or a '/quit' command was issued...)
        if @data.length > 0
          raise MTik::Error.new("Sanity check failed on receipt of '!fatal' message: #{@data.length} more bytes remain to be parsed. API utility may be buggy.")
        end

        quit = false
        ## Iterate over all incomplete requests:
        @requests.each_value do |r|
          if r.done?
            raise MTik::Error.new("Sanity check failed: an outstanding request was flagged as done!")
          end
          @requests.delete(r.tag)
          r.done!
          if r.await_completion
            ## Pass partial reply to callback along with '!fatal' sentence
            r.callback(sentence)
          end
          ## Was this a '/quit' command?
          if r.command == '/quit'
            quit = true
            ## Attach the untagged '!fatal' reply to the '/quit' command:
            r.reply.push(sentence)
          end
        end

        ## Raise fatal error if there wasn't a '/quit' command:
        unless quit
          raise MTik::FatalError.new(sentence.key?('message') ? sentence['message'] : '')
        end
        ## On /quit, just return:
        @parsing = oldparsing
        return
      end

      ## We expect ALL sentences thus far to be tagged:
      unless sentence.key?('.tag')
        ## This code tags EVERY request, so NO RESPONSE should be untagged
        ## except maybe a '!fatal' error...
        raise MTik::Error.new("Unexected untagged response received.")
      end
      rtag = sentence['.tag']

      ## Find which request this reply sentence belongs to:
      unless @requests.key?(rtag)
        raise MTik::Error.new("Unknown tag '#{rtag}' found in response.")
      end
      request = @requests[rtag]

      ## Sanity check: No sentences should arrive for completed requests.
      if request.done?
        raise MTik::Error.new("Unexpected new reply sentence received for already-completed request.")
      end

      ## Add the sentence to the request's reply:
      request.reply.push(sentence)

      ## On '!done', flag the request response as complete:
      if sentence.key?('!done')
        request.done!
        ## Pass the data to the callback:
        request.callback(sentence)
        ## Remove the request:
        @requests.delete(request.tag)
      else
        unless request.await_completion && !request.done?
          ## Pass the data to the callback:
          request.callback(sentence)
        end
      end
    ## Keep reading sentences as long as there is data to be parsed:
    end while @data.length > 0
    @parsing = oldparsing
  end

  ## Alias of send_request() with param 1 set to false
  def request_each(command, *args, &callback)
    return send_request(false, command, *args, &callback)
  end

  ## Alias of send_request() with param 1 set to true
  def request(command, *args, &callback)
    return send_request(true, command, *args, &callback)
  end

  ## Send a request to the device.
  ## +await_completion+::  Boolean indicating whether to execute callbacks
  ##                       only once upon request completion (if set to _true_)
  ##                       or to execute for every received complete sentence
  ##                       (if set to _false_).  ALTERNATIVELY, this parameter
  ##                       may be an object (MTik::Request) to be sent, in which
  ##                       case any command and/or arguments will be treated as
  ##                       additional arguments to the request contained in the
  ##                       object.
  ## +command+::           The command to be executed.
  ## +args+::              Zero or more arguments to the command
  ## +callback+::          Proc/lambda code (or code block if not provided as
  ##                       an argument) to be called.  (See the +await_completion+
  ##
  def send_request(await_completion, command, *args, &callback)
    if await_completion.is_a?(MTik::Request)
      req = await_completion
      if req.done?
        raise MTik::Error.new("Cannot MTik#send_request() with an already-completed MTik::Request object.")
      end
      req.addarg(command)
      req.addargs(*args)
    else
      req = MTik::Request.new(await_completion, command, *args, &callback)
    end
    ## Add the new outstanding request
    @requests[req.tag] = req

    if MTik::debug || MTik::verbose
      req.each do |x|
        STDERR.print "<<< '#{x}' (#{x.length})\n"
      end
    end
    STDERR.print "<<< END-OF-SENTENCE\n\n" if MTik::debug || MTik::verbose

    req.conn(self) ## Associate the request to this connection object:
    return req.send
  end

  ## Send the request object over the socket
  def xmit(req)
    if @ssl_sock
      @ssl_sock.write(req.request)
    else
      @sock.send(req.request, 0)
    end

    return req
  end

  def recv(buffer_size)
    if @ssl_sock
      recv_openssl(buffer_size)
    else
      @sock.recv(buffer_size)
    end
  end

  # 2 cases for backwards compatibility
  def recv_openssl(buffer_size)
    if OpenSSL::SSL.const_defined? 'SSLErrorWaitReadable'.freeze
      begin
        @ssl_sock.read_nonblock(buffer_size)
      rescue OpenSSL::SSL::SSLErrorWaitReadable
        ''
      end
    else
      begin
        @ssl_sock.read_nonblock(buffer_size)
      rescue OpenSSL::SSL::SSLError => e
        return '' if e.message == 'read would block'.freeze
        raise e
      end
    end
  end

  ## Send a command, then wait for the command to complete, then return
  ## the completed reply.
  ##
  ## +command+::  The command to execute
  ## +args+::     Arguments (if any)
  ## +callback+:: Proc/lambda or code block to act as callback
  ##
  ## *NOTE*: This call has its own event loop that will cycle until
  ## the command in question completes. You should:
  ## * NOT call get_reply with a command that may not
  ##   complete with a "!done" response on its own
  ##   (with no additional intervention); and
  ## * BE CAREFUL to understand how things interact if
  ##   you mix this call with requests that generate
  ##   continuous output.
  def get_reply(command, *args, &callback)
    req = send_request(true, command, *args, &callback)
    wait_for_request(req)
    return req.reply
  end

  ## This is exactly like get_reply() except that EACH
  ## sentence read will result in the passed Proc/block
  ## being called instead of just the final "!done" reply
  def get_reply_each(command, *args, &callback)
    req = send_request(false, command, *args, &callback)
    wait_for_request(req)
    return req.reply
  end

  ## Close the connection.
  def close
    return if @sock.nil? and @ssl_sock.nil?
    @ssl_sock.close if @ssl_sock and !@ssl_sock.closed?
    @sock.close if @sock and !@sock.closed?
    @ssl_sock = nil
    @sock = nil
  end

  ## Is the connection open?
  def connected?
    return @sock.nil? ? false : true
  end

  ## Because of differences in the Ruby 1.8.x vs 1.9.x 'String' class,
  ## a 'cbyte' utility method that returns the character byte at the
  ## specified offset of the supplied string is here defined so that
  ## there is a single consistent method that will work with either
  ## Ruby version (treating all strings as 8-bit binary data in Ruby 1.9+)
  if RUBY_VERSION >= '1.9.0'
    ## Return the byte at the offset specified from the
    ## Ruby 1.9 8-bit binary string as an integer.
    def cbyte(str, offset)
      return str.encode(Encoding::BINARY)[offset].ord
    end
  else
    ## Return the byte at the offset specified from the
    ## Ruby 1.8.x character string (Ruby 1.8 doesn't
    ## support multi-byte characters so all characters
    ## are 8-bits in length).
    def cbyte(str, offset)
      return str[offset]
    end
  end

  ## Parse binary string data and return the first 'Tik "word"
  ## found:
  def get_tikword(data)
    unless data.is_a?(String)
      raise ArgumentError.new("bad argument: expected String but got #{data.class}")
    end

    ## Be sure we're working in 8-bit binary (Ruby 1.9+):
    if RUBY_VERSION >= '1.9.0'
      data.force_encoding(Encoding::BINARY)
    end

    unless data.length > 0
      return 0, nil   ## Not enough data to parse
    end

    ## The first byte tells us how the word length is encoded:
    len = 0
    len_byte = cbyte(data, 0)
    if len_byte & 0x80 == 0
      len = len_byte & 0x7f
      i = 1
    elsif len_byte & 0x40 == 0
      unless data.length > 0x81
        return 0, nil   ## Not enough data to parse
      end
      len = ((len_byte & 0x3f) << 8) | cbyte(data, 1)
      i = 2
    elsif len_byte & 0x20 == 0
      unless data.length > 0x4002
        return 0, nil   ## Not enough data to parse
      end
      len = ((len_byte & 0x1f) << 16) | (cbyte(data, 1) << 8) | cbyte(data, 2)
      i = 3
    elsif len_byte & 0x10 == 0
      unless data.length > 0x200003
        return 0, nil   ## Not enough data to parse
      end
      len = ((len_byte & 0x0f) << 24) | (cbyte(data, 1) << 16) | (cbyte(data, 2) << 8) | cbyte(data, 3)
      i = 4
    elsif len_byte == 0xf0
      len = (cbyte(data, 1) << 24) | (cbyte(data, 2) << 16) | (cbyte(data, 3) << 8) | cbyte(data, 4)
      i = 5
    else
      ## This will also catch reserved control words where the first byte is >= 0xf8
      raise ArgumentError.new("bad argument: String length encoding is invalid")
    end
    if data.length - i < len
      return 0, nil   ## Not enough data to parse
    end
    return i + len, data[i, len]
  end

  ## Utility to execute the "/tool/fetch" command, instructing
  ## the device to download a file from the specified URL.
  ## Status updates are provided via the provided callback.
  ## +url+::      The URL to fetch the file from
  ## +filename+:: The filename to use on the device
  ## +timeout+::  Cancel command if a reply indicates the
  ##              download has stalled for +timeout+ seconds.
  ##              This is disabled by default. Disable by
  ##              setting +timeout+ to nil or zero, enable by
  ##              supplying a positive number of seconds.
  ##              (OPTIONAL argument)
  ## +callback+:: Callback called for status updates.
  ##
  ## The arguments passed to the callback are:
  ## +status+::   Either 'downloading', 'connecting',
  ##              'failed', 'requesting', or 'finished',
  ##              otherwise a '!trap' error occured,
  ##              and the value is the trap message.
  ## +total+::    Final expected file size in bytes
  ## +bytes+::    Number of bytes transferred so far
  ## +request+::  The MTik::Request object
  def fetch(url, filename=nil, timeout=nil, &callback)
    require 'uri'

    uri = URI(url)
    filename = File.basename(uri.path) if filename.nil?

    total  = bytes = oldbytes = 0
    status = ''
    done   = false
    lastactivity = Time.now

    ## RouterOS versions 4.9 and prior (not sure if this version cut-off
    ## is exactly right) would accept the url parameter, but failed to
    ## download the files.  So for versions older than this, we'll use
    ## the mode/src-path/port parameters instead if possible.
    if !@os_version.nil? && lambda {|a,b|
      sr = %r{(?:\.|rc|beta|alpha)}
      a = a.split(sr).map{|i| i.to_i}
      b = b.split(sr).map{|i| i.to_i}
      i = 0
      while i < a.size && i < b.size
        return -1 if a[i] < b[i]
        return  1 if a[i] > b[i]
        i += 1
      end
      return a.size <=> b.size
    }.call(@os_version, '4.9') < 1
      command = [
        '/tool/fetch', '=mode=' + uri.scheme,
        '=src-path=' + uri.path + (uri.query.size > 0 ? '?' + uri.query : ''),
        '=dst-path=' + filename
      ]
      case uri.scheme
      when 'http'
        command << '=port=80'
      when 'https'
        command << '=port=443'
      end
    else
      command = [
        '/tool/fetch',
        '=url=' + url,
        '=dst-path=' + filename
      ]
    end

    req = get_reply_each(command[0], *command[1..-1])  do |r, s|
      if s.key?('!re') && !done
        unless s.key?('status')
          raise MTik::Error.new("Unknown response to '/tool/fetch': missing 'status' in response.")
        end
        status = s['status']
        case status
        when 'downloading'
          total = s['total'].to_i
          bytes = s['downloaded'].to_i
          if bytes != oldbytes
            lastactivity = Time.now
          elsif timeout != 0 && !timeout.nil? && Time.now - lastactivity > timeout
            ## Cancel the request (idle too long):
            get_reply('/cancel', '=tag=' + r.tag) {}
          end
          callback.call(status, total, bytes, r)
        when 'connecting', 'requesting'
          callback.call(status, 0, 0, r)
        when 'failed', 'finished'
          bytes = total if status == 'finished'
          callback.call(status, total, bytes, r)
          done = true
          ## Now terminate the download request (since it's done):
          get_reply('/cancel', '=tag=' + r.tag) {}
        else
          raise MTik::Error.new("Unknown status in '/tool/fetch' response: '#{status}'")
        end
      elsif s.key?('!trap')
        ## Pass trap message back (unless finished--in which case we
        ## ignore the 'interrrupted' trap message):
        callback.call(s['message'], total, bytes, r) if !done
      end
    end
  end

  ## Utility to check and update MikroTik device settings within a
  ## specified subsection of the device.
  def update_values(cmdpath, keyvaluepairs, &callback)
    get_reply_each(cmdpath + '/getall') do |req, s|
      if s.key?('!re')
        ## Iterate over each key/value pair and check if the current
        ## device subsection's "getall" matches one of the keys:
        keyvaluepairs.each do |key, value|
          ## If the key is a String, it matches if the reply sentence
          ## has a matching key.  If the key is a Regexp, then iterate
          ## over ALL sentence keys and find all items that match.
          matchedkey = nil
          if key.is_a?(String)
            if s.key?(key)
              matchedkey = key
            end
          elsif key.is_a?(Regexp)
            s.each_key do |skey|
              if key.match(skey)
                matchedkey = skey
              end
            end
          elsif key.is_a(Array)
            ## Iterate over each array item and perform matching on
            ## each String or Regexp therein:
            key.each do |keyitem|
              if keyitem.is_a?(String)
                if s.key?(keyitem)
                  matchedkey = keyitem
                end
              elsif keyitem.is_a?(Regexp)
                ## Iterate over each sentence key and test matching
                s.each_key do |skey|
                  if key.match(skey)
                    ## Check setting's current value:
                    if value.is_a?(Proc)
                      v = value.call(skey, s[skey])
                    elsif value.is_a?(String)
                      v = value
                    else
                      raise MTik::Error.new("Invalid settings value class '#{value}' (expected String or Proc)")
                    end
                    if s[skey] != v
                      ## Update setting from s[skey] to v
                    end
                  end
                end
              else
                raise MTik::Error.new("Invalid settings match class '#{keyitem}' (expected Regexp or String)")
              end
            end
          else
            raise MTik::Error.new("Invalid settings match class '#{keyitem}' (expected Array, Regexp, or String)")
          end

          if s.key?(key)
            ## A key matches! && s[k] != v
            oldv = s[k]
            get_reply(cmdpath + '/set', '='+k+'='+v) do |r, sn|
              trap = r.reply.find_sentence('!trap')
              unless trap.nil?
                raise MTik::Error.new("Trap while executing '#{cmdpath}/set =#{k}=#{v}': #{trap['message']}")
              end
              callback.call(cmdpath + '/' + k, oldv, v)
            end
          end
        end
      end
    end
  end
end


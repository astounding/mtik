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

module MTik
  require_relative 'mtik/error.rb'
  require_relative 'mtik/fatalerror.rb'
  require_relative 'mtik/timeouterror.rb'
  require_relative 'mtik/request.rb'
  require_relative 'mtik/reply.rb'
  require_relative 'mtik/connection.rb'

  ## Default MikroTik RouterOS API TCP port:
  PORT = 8728
  ## Default MikroTik RouterOS API-SSL TCP port:
  PORT_SSL = 8729
  ## Default username to use if none is specified:
  USER = 'admin'
  ## Default password to use if none is specified:
  PASS = ''
  ## Connection timeout default -- *NOT USED* 
  CONN_TIMEOUT = 60
  ## Command timeout -- The maximum number of seconds to wait for more
  ## API data when expecting one or more command responses.
  CMD_TIMEOUT  = 60

  ## Maximum number of replies before a command is auto-canceled:
  MAXREPLIES   = 1000

  ## SSL is set to false by default
  USE_SSL = false

  @verbose = false
  @debug   = false

  ## Access the current verbose setting (boolean)
  def self.verbose
    return @verbose
  end

  ## Change the current verbose setting (boolean)
  def self.verbose=(x)
    return @verbose = x
  end

  ## Access the current debug setting (boolean)
  def self.debug
    return @debug
  end

  ## Change the current debug setting (boolean)
  def self.debug=(x)
    return @debug = x
  end


  ## Act as an interactive client with the device, accepting user
  ## input from STDIN.
  def self.interactive_client(host, user, pass)
    old_verbose = MTik::verbose
    MTik::verbose = true
    begin
      tk = MTik::Connection.new(:host => host, :user => user, :pass => pass)
    rescue MTik::Error, Errno::ECONNREFUSED => e
      print "=== LOGIN ERROR: #{e.message}\n"
      exit
    end

    while true
      print "\nCommand (/quit to end): "
      cmd = STDIN.gets.sub(/^\s+/, '').sub(/\s*[\r\n]*$/, '')
      maxreply = 0
      m = /^(\d+):/.match(cmd)
      unless m.nil?
        maxreply = m[1].to_i
        cmd.sub!(/^\d+:/, '')
      end
      args  = cmd.split(/\s+/)
      cmd   = args.shift
      next if cmd == ''
      break if cmd == '/quit'
      unless /^(?:\/[a-zA-Z0-9-]+)+$/.match(cmd)
        print "=== INVALID COMMAND: #{cmd}\n" if MTik::debug || MTik::verbose
        break
      end
      print "=== COMMAND: #{cmd}\n" if MTik::debug || MTik::verbose
      trap  = false
      count = 0
      state = 0
      begin
        tk.send_request(false, cmd, args) do |req, sentence|
          if sentence.key?('!trap')
            trap = sentence
            print "=== TRAP: '" + (trap.key?('message') ? trap['message'] : "UNKNOWN") + "'\n\n"
          elsif sentence.key?('!re')
            count += 1
            ## Auto-cancel any '/tool/fetch' commands that have finished,
            ## or commands that have received the specified number of
            ## replies:
            if req.state == :sent && (
              cmd == '/tool/fetch' && sentence['status'] == 'finished'
            ) || (maxreply > 0 && count == maxreply)
              state = 2
              req.cancel do |r, s|  
                state = 1
              end
            end
          elsif !sentence.key?('!done') && !sentence.key?('!fatal')
            raise MTik::Error.new("Unknown or unexpected reply sentence type.")
          end
          if state == 0 && req.done?
            state = 1
          end
        end
        while state != 1
          tk.wait_for_reply
        end
      rescue MTik::Error => e
        print "=== ERROR: #{e.message}\n"
      end
      unless tk.connected?
        begin
          tk.login
        rescue MTik::Error => e
          print "=== LOGIN ERROR: #{e.message}\n"
          tk.close
          exit
        end
      end
    end
 
    reply = tk.get_reply('/quit')
    unless reply[0].key?('!fatal')
      raise MTik::Error.new("Unexpected response to '/quit' command.")
    end

    ## Extract any device-provided message from the '!fatal' response
    ## to the /quit command:
    print "=== SESSION TERMINATED"
    message = ''
    reply[0].each_key do |key|
      next if key == '!fatal'
      message += "'#{key}'"
      unless reply[0][key].nil?
        message += " => '#{reply[0][key]}'"
      end
    end
    if message.length > 0
      print ": " + message
    else
      print " ==="
    end
    print "\n\n"

    unless tk.connected?
      print "=== Disconnected ===\n\n"
    else
      ## In theory, this should never execute:
      tk.close
    end

    MTik::verbose = old_verbose
  end


  ## An all-in-one function to instantiate, connect, send one or
  ## more commands, retrieve the response(s), close the connection,
  ## and return the response(s).
  ##
  ## PARAMETERS:
  ##   All parameters supplied to this method are contained in a
  ##   single hash.  Here are available hash keys:
  ##
  ##     :host    => the host name or IP to connect to
  ##     :user    => the API user ID to authenticate with
  ##     :pass    => the API password to authenticate with
  ##     :command => one or more API commands to execute
  ##     :limit   => an OPTIONAL integer reply limit
  ##
  ## The :command parameter may be:
  ##   * A single string representing a single API command to execute
  ##   * An array of strings in which case the first string is the API
  ##     command to execute and each subsequent array item is an API
  ##     parameter or argument.
  ##   * An array of arrays -- Multiple API command may be executed
  ##     in sequence.  Each subarray is an array of strings containing
  ##     an API command and zero or more parameters.
  ##
  ## The :limit parameter if present specifies an integer.  This parameter
  ## is to be used whenever executing one or more API commands that do
  ## not terminate with a '!done' response sentence, but instead keep
  ## sending '!re' reply sentences.
  ##
  ## An exception is the '/tools/fetch' API command, which this method
  ## will auto-cancel when it finishes.
  ##
  ## Regarding the :limit parameter:
  ##  * If present and the integer is zero or negative, THERE WILL BE
  ##    NO LIMIT ENFORCED on the number of replies from each API command.
  ##    *WARNING:* If you do NOT limit the number of replies when
  ##    executing an API command like <i>"/interface/montitor-traffic"</i>
  ##    this method may not ever terminate and may consume memory
  ##    buffering replies until resources are exhausted.
  ##  * If present and a positive integer, each API command may at
  ##    most receive the specified number of reply sentences, after which
  ##    the command will automatically be canceled.  This is useful
  ##    to terminate commands that would otherwise keep sending output
  ##    forever.
  ##  * If NOT present, or if nil, the default reply limit as contained
  ##    in the MAXREPLIES constant will be enforced. *WARNING:* This
  ##    default limit could be so large that this method would not
  ##    return for a long time, waiting for the number of replies.
  ##
  ## Remember that the limit applies separately to each API command
  ## executed.
  def self.command(args)
    tk = MTik::Connection.new(
      :host => args[:host],
      :user => args[:user],
      :pass => args[:pass],
      :port => args[:port],
      :conn_timeout => args[:conn_timeout],
      :cmd_timeout  => args[:cmd_timeout]
    )
    limit = args[:limit]  ## Optional reply limit
    cmd = args[:command]
    replies = Array.new
    if cmd.is_a?(String)
      ## Single command, no arguments
      cmd = [ [ cmd ] ]
    elsif cmd.is_a?(Array) && !cmd[0].is_a?(Array)
      ## Single command, possibly arguments
      cmd = [ cmd ]
    end

    cmd.each_index do |i|
      c = cmd[i]
      replycount = 0
      tk.send_request(false, c[0], c[1,c.length-1]) do |req, sentence|
        replycount += 1
        if c[0] == '/tool/fetch'
          if sentence['status'] == 'finished' && req.state == :sent
            ## Cancel 'finished' fetch commands
            req.cancel
          end
        elsif req.state == :sent && (
          limit.nil? ? (replycount >= MAXREPLIES) : (limit > 0 && replycount >= limit)
        )
          ## Auto-cancel any command after the maximum number of replies:
          req.cancel
        end
        if sentence.key?('!done')
          replies[i] = req.reply
        end
      end
    end

    tk.wait_all ## Event loop -- wait for all commands to finish
    tk.get_reply('/quit')
    tk.close
    return replies
  end

end


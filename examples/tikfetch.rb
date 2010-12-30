#!/usr/bin/env ruby
########################################################################
#--
#
# FILE:     fetch.rb -- Example of using the Ruby MikroTik API in Ruby
#
#++
# Author::    Aaron D. Gifford - http://www.aarongifford.com/
# Copyright:: Copyright (c) 2009-2010, InfoWest, Inc.
# License::   BSD license
#--
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, the above list of authors and contributors, this list of
#    conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the author(s) or copyright holder(s) nor the
#    names of any contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S), AUTHOR(S) AND
# CONTRIBUTORS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
# IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), AUTHOR(S), OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# DCONSEQUENTIAL AMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.
########################################################################
$LOAD_PATH.unshift(File.dirname(__FILE__)+'/../lib')

require 'rubygems'
require 'mtik'

## Uncomment this (set $VERBOSE to true) if you want crazy verbose
## output of all API interactions:
#MTik::verbose = true

if ARGV.length < 4
  print "Usage: #{$0} <device> <user> <pass> <url> [<localfilename> [<url> [<localfilename> ... ]]]\n"
  exit
end

host = ARGV.shift
user = ARGV.shift
pass = ARGV.shift
begin
  mt = MTik::Connection.new(:host=>host, :user=>user, :pass=>pass)
rescue Errno::ETIMEDOUT, Errno::ENETUNREACH, Errno::EHOSTUNREACH, MTik::Error => e
  print ">>> ERROR CONNECTING: #{e}\n"
  exit
end

## List all files:
files = Hash.new
mt.get_reply_each('/file/getall') do |req, s|
  unless s.key?('!done')
    files[s['name']] = true
  end
end

while ARGV.length > 0
  url = ARGV.shift
  if ARGV.length > 0
    filename = ARGV.shift
  else
    filename = File.basename(url)
  end
  if files.key?(filename)
    print ">>> ERROR: There is a file named '#{filename}' already on the device.\n"
  else
    print ">>> OK: Fetching file '#{filename}' from URL '#{url}'...\n"
    oldbytes = 0
    totalbytes = nil
    oldtime  = starttime = Time.now
    mt.fetch(url, filename, 120) do |status, total, bytes, req|
      now = Time.now
      case status
      when 'connecting'
        starttime = now
        print ">>> OK: Connecting to '#{url}' to download file '#{filename}'\n"
      when 'requesting'
        starttime = now
        print ">> OK: Connected.  Sending request for '#{filename}'...\n"
      when 'downloading'
        # Unfortunately, the 'total' parameter is only valid for a
        # 'downloading' status update, so we save the value.
        totalbytes = total if totalbytes.nil?
        print (
          ">>> OK: Downloaded #{bytes} KB of #{total} KB " +
          '(%0.2f KBps, %0.2f avgKBps) of ' +
          "'#{filename}' " +
          (total > 0 ? '%0.2f' % (100.0*bytes/total) : '0') +
          '%%' + (oldbytes == bytes ? ' *STALLED*' : '') +  "\n"
        ) % [(bytes-oldbytes)/(now-oldtime), bytes/(now-starttime)]
        oldbytes = bytes
      when 'finished'
        unless totalbytes.nil?
          print (
            ">>> OK: Downloaded #{totalbytes} KB of #{totalbytes} KB " +
            '(%0.2f KBps, %0.2f avgKBps) of ' +
            "'#{filename}' 100.00%%\n"
          ) % [(totalbytes-oldbytes)/(now-oldtime), totalbytes/(now-starttime)]
        end
        print ">>> OK: File '#{filename}' download finished in #{'%0.2f' % [now-starttime]} seconds.\n"
      when 'failed'
        print ">>> ERROR: File '#{filename}' download failed!\n"
      else
        print ">>> ERROR: The following trap error occured: #{status}\n"
      end
      oldtime  = now
    end
  end
end
mt.wait_all

print "\n"
print "SIZE        CREATED               FILENAME\n"
print "====================================================================\n"
mt.get_reply_each('/file/getall') do |req, s|
  unless s.key?('!done')
    print "#{(s['size']+'        ')[0,10]}  #{s['creation-time']}  #{s['name']}\n"
  end
end

print "\n"

mt.close


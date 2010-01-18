#!/usr/local/bin/ruby
########################################################################
#--
#
# FILE:     json.rb -- Example of using the Ruby MikroTik API in Ruby
# VERSION:  3.3.0
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
require 'rubygems'
require 'mtik'

unless ARGV.length > 3
  STDERR.print("Usage: #{$0} <host> <user> <pass> <command> [<args>...]\n")
  exit(-1)
end

## Quick-n-dirty JSON-ifyer--For any real JSON application
## use "require 'json' and do it right.
def json_str(str)
  newstr = "'"
  str.each_byte do |byte|
    if byte == 92     ## back-slash
      newstr += '\\\\'
    elsif byte == 34  ## double-quote
      newstr += '\\"'
    elseif byte == 39 ## apostrophe/single-quote
      newstr += '\\' + "'"
    elseif byte == 47 ## forward-slash
      newstr += '\\/'
    elsif byte == 8   ## backspace
      newstr += '\\b'
    elsif byte == 12  ## formfeed
      newstr += '\\f'
    elsif byte == 10  ## linefeed
      newstr += '\\n'
    elsif byte == 13  ## carriage return
      newstr += '\\r'
    elsif byte == 9   ## horizontal tab
      newstr += '\\t'
    elsif byte == 38  ## ampersand
      newstr += sprintf('\\u%04X', byte)
    elsif byte == 60  ## less-than
      newstr += sprintf('\\u%04X', byte)
    elsif byte == 62  ## greater-than
      newstr += sprintf('\\u%04X', byte)
    elsif byte >= 32 && byte <= 126
      newstr += byte.chr
    else
      newstr += sprintf('\\u%04X', byte)
    end
  end
  return newstr + "'"
end

def json_reply(response)
  return '[' +
  response.map do |sentence| 
    '{' +
    sentence.map do |key, value|
      json_str(key) + ': ' +
      if value.nil?
        'NULL'
      elsif /^-?(?:\d+(\.\d+)?|\d*\.\d+)$/.match(value)
        value
      else
        json_str(value)
      end
    end.join(',') +
    '}'
  end.join(',') +
  ']'
end

print json_reply(
  MTik::command(
    :host=>ARGV[0],
    :user=>ARGV[1],
    :pass=>ARGV[2],
    :command=>ARGV[3, ARGV.length-1]
  )[0]
) + "\n"


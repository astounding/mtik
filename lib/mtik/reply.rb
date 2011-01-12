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

## A MikroTik API reply is stored as an array of response sentences. Each
## sentence is a key/value Hash object. The MTik::Reply class is simply
## a basic Ruby Array with find_sentence and find_sentences methods added.
class MTik::Reply < Array
  ## This method is nearly identical to Array.select{|i| i.key?(key)}[0]
  ## except that this method short-circuits and returns when the first
  ## match is found.
  def find_sentence(key)
    self.each do |sentence|
      return sentence if sentence.key?(key)
    end
    return nil
  end

  ## This method is simply an alias for Array.select{|i| i.key?(key)}
  def find_sentences(key)
    return self.select do |sentence|
      sentence.key?(key)
    end
  end
end


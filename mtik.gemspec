
Gem::Specification.new do |spec|
  spec.name         = 'mtik'
  spec.version      = '3.0.2'
  spec.date         = File.mtime('VERSION.txt')
  spec.author       = 'Aaron D. Gifford'
  spec.email        = 'email_not_accepted@aarongifford.com'
  spec.homepage     = 'http://www.aarongifford.com/computers/mtik/'
  spec.summary      = 'MTik implements the MikroTik RouterOS API for use in Ruby.'
  spec.description  = 'MTik implements the MikroTik RouterOS API for use in Ruby.'
  spec.has_rdoc     = true ## Only partially true currently
  spec.rubyforge_project = 'mtik'
  spec.extra_rdoc_files  = [ 'README.txt' ]
  spec.require_paths     = [ 'lib' ]
  spec.files             = [
    'CHANGELOG.txt',
    'LICENSE.txt',
    'README.txt',
    'VERSION.txt',
    'examples/tikcli.rb',
    'examples/tikcommand.rb',
    'examples/tikfetch.rb',
    'examples/tikjson.rb',
    'lib/mtik.rb',
    'lib/mtik/connection.rb',
    'lib/mtik/error.rb',
    'lib/mtik/fatalerror.rb',
    'lib/mtik/reply.rb',
    'lib/mtik/request.rb',
    'lib/mtik/timeouterror.rb'
  ]
end

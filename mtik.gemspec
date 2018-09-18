Gem::Specification.new do |spec|
  spec.name         = 'mtik'
  spec.version      = File.open('VERSION.txt','r').to_a.join.strip
  spec.date         = File.mtime('VERSION.txt')
  spec.author       = 'Aaron D. Gifford'
  spec.email        = 'email_not_accepted@aarongifford.com'
  spec.homepage     = 'http://www.aarongifford.com/computers/mtik/'
  spec.summary      = 'MTik implements the MikroTik RouterOS API for use in Ruby.'
  spec.description  = 'MTik implements the MikroTik RouterOS API for use in Ruby.'
  spec.rubyforge_project = 'mtik'
  spec.extra_rdoc_files  = [ 'README.txt' ]
  spec.require_paths     = [ 'lib' ]
  spec.files             = [
    'CHANGELOG.txt',
    'LICENSE.txt',
    'README.txt',
    'VERSION.txt',
    'Rakefile',
    'examples/tikjson.rb',
    'bin/tikcli',
    'bin/tikcommand',
    'bin/tikfetch',
    'lib/mtik.rb',
    'lib/mtik/connection.rb',
    'lib/mtik/error.rb',
    'lib/mtik/fatalerror.rb',
    'lib/mtik/reply.rb',
    'lib/mtik/request.rb',
    'lib/mtik/timeouterror.rb'
  ]
  spec.executables = [ 'tikcli', 'tikcommand', 'tikfetch' ]
end

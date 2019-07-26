require 'rubygems'
require 'rubygems/package_task'
require 'rdoc/task'

gemspec = Gem::Specification.load('mtik.gemspec')

Gem::PackageTask.new(gemspec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

RDoc::Task.new do |rdoc|
  rdoc.name     = 'rdoc'
  rdoc.main     = 'README.txt'
  rdoc.rdoc_dir = 'doc'
  rdoc.rdoc_files.include('README.txt', 'LICENSE.txt', 'CHANGELOG.txt', 'lib/**/*.rb')
end

task :default => [
  'pkg/mtik-' + File.open('VERSION.txt','r').to_a.join.strip + '.gem',
  :rdoc
]


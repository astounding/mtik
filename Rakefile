require 'rubygems'
require 'rubygems/package_task'
require 'rdoc/task'

task :build do
  puts `gem build mtik.gemspec`
end

task :install do
  puts `gem build mtik.gemspec`
  puts `gem install ./mtik-#{File.open('VERSION.txt','r').to_a.join.strip}.gem`
end

RDoc::Task.new do |rdoc|
  rdoc.name     = 'rdoc'
  rdoc.main     = 'README.txt'
  rdoc.rdoc_dir = 'doc'
  rdoc.rdoc_files.include('README.txt', 'LICENSE.txt', 'CHANGELOG.txt', 'lib/**/*.rb')
end

task :default => [
  :build,
  :rdoc
]


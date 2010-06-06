
begin
  require 'bones'
rescue LoadError
  abort '### Please install the "bones" gem ###'
end

task :default => 'test:run'
task 'gem:release' => 'test:run'

Bones {
  name  'zmqmachine'
  authors  'Chuck Remes'
  email    'cremes@mac.com'
  url      'http://github.com/chuckremes/zmqmachine'
  ignore_file '.gitignore'
  readme_file 'README.rdoc'
}


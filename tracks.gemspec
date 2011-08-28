Gem::Specification.new do |s|
  s.name = "tracks"
  s.version = "0.0.1"
  s.summary = "Threaded Ruby Rack HTTP server"
  s.description = "A bare-bones Ruby HTTP server that talks Rack and uses a thread per connection model of concurrency."
  s.files = %W{lib}.map {|dir| Dir["#{dir}/**/*.rb"]}.flatten << "README.rdoc"
  s.require_path = "lib"
  s.rdoc_options = ["--main", "README.rdoc", "--charset", "utf-8"]
  s.extra_rdoc_files = ["README.rdoc"]
  s.author = "Matthew Sadler"
  s.email = "mat@sourcetagsandcodes.com"
  s.homepage = "http://github.com/matsadler/tracks"
  s.add_dependency("rack", ">= 1.0.0")
  s.add_dependency("http_tools", "~> 0.4.1")
end

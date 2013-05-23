require 'thread'
require 'timeout'
require 'forwardable'
require 'rubygems'
require 'rack'

warn "WARNING silencing #puts (#{__FILE__} #{__LINE__ + 1})"
module Kernel; def puts(*args) end end

module TracksTestHelper
  
  def setup
    @hello_app = Proc.new do |env|
      [200, {"Content-Length" => "13"}, ["Hello world!\n"]]
    end
    
    @echo_app = Rack::ContentLength.new(Proc.new do |env|
      [200, {}, [env["rack.input"].read]]
    end)
  end
  
  def teardown
    Tracks.shutdown
    sleep 0.1
  end
  
  def serve(app)
    host, port = "localhost", 8421
    thread = Thread.new {Tracks.run(app, :Host => host, :Port => port)}
    thread.abort_on_exception = true
    sleep 0.1
    [host, port]
  end
  
  def wait_for_response
    sleep 0.01
  end
  
  def silence(io)
    original_fileno = io.fileno
    io.reopen("/dev/null")
    yield
    io.reopen(IO.open(original_fileno))
  end
end

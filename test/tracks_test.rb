require File.expand_path("../../lib/tracks", __FILE__)
require File.expand_path("../test_helper", __FILE__)
require "test/unit"

class TracksTest < Test::Unit::TestCase
  include TracksTestHelper
  
  def test_get
    host, port = serve(@hello_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
  end
  
  def test_chunked_get
    chunked_body = Object.new
    def chunked_body.each
      yield "Hello"
      sleep 0.05
      yield " world"
      sleep 0.05
      yield "!\n"
    end
    chunked_app = Rack::Chunked.new(Proc.new do |env|
      [200, {}, chunked_body]
    end)
    host, port = serve(chunked_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: Keep-Alive\r\n\r\n5\r\nHello\r\n",
      socket.sysread(1024))
    assert_equal("6\r\n world\r\n", socket.sysread(1024))
    assert_equal("2\r\n!\n\r\n0\r\n\r\n", socket.sysread(1024))
  end
  
  def test_http_1_1_implicit_keep_alive
    host, port = serve(@hello_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
  end
  
  def test_http_1_0_implicit_close
    host, port = serve(@hello_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_http_1_1_explicit_close
    host, port = serve(@hello_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_http_1_0_explicit_keep_alive
    host, port = serve(@hello_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: Keep-Alive\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_http_1_1_implicit_close_without_content_length
    host, port = serve(Proc.new {|env| [200, {}, ["Hello world!\n"]]})
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_http_1_1_implicit_keep_alive_on_no_body_response
    host, port = serve(Proc.new {|env| [204, {}, []]})
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 204 No Content\r\nConnection: Keep-Alive\r\n\r\n",
      socket.sysread(1024))
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 204 No Content\r\nConnection: Keep-Alive\r\n\r\n",
      socket.sysread(1024))
  end
  
  def test_http_1_0_explicit_keep_alive_closes_without_content_length
    host, port = serve(Proc.new {|env| [200, {}, ["Hello world!\n"]]})
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: Keep-Alive\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_http_1_0_explicit_keep_alive_on_no_body_response
    host, port = serve(Proc.new {|env| [204, {}, []]})
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: Keep-Alive\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 204 No Content\r\nConnection: Keep-Alive\r\n\r\n",
      socket.sysread(1024))
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: Keep-Alive\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 204 No Content\r\nConnection: Keep-Alive\r\n\r\n",
      socket.sysread(1024))
  end
  
  # TODO: Transfer-Encoding: chunked versions of keep-alive/close tests needed
  
  def test_app_can_force_http_1_1_close
    host, port = serve(Proc.new do |env|
      [200, {"Content-Length" => "13", "Connection" => "close"}, ["Hello world!\n"]]
    end)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_app_can_force_http_1_1_close_case_insensitive
    host, port = serve(Proc.new do |env|
      [200, {"Content-Length" => "13", "cOnNeCtIoN" => "cLoSe"}, ["Hello world!\n"]]
    end)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_app_can_force_http_1_0_keep_alive
    host, port = serve(Proc.new do |env|
      [200, {"Content-Length" => "13", "Connection" => "Keep-Alive"}, ["Hello world!\n"]]
    end)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
    
    socket << "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
  end
  
  def test_pipeline
    host, port = serve(@hello_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n" +
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
  end
  
  def test_multiple_clients
    host, port = serve(@hello_app)
    socket1 = TCPSocket.new(host, port)
    socket2 = TCPSocket.new(host, port)
    
    socket1 << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    socket2 << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket1.sysread(1024))
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket2.sysread(1024))
  end
  
  def test_post
    host, port = serve(@echo_app)
    socket = TCPSocket.new(host, port)
    
    socket << "POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 3\r\n\r\nfoo"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: Keep-Alive\r\n\r\nfoo",
      socket.sysread(1024))
  end
  
  def test_chunked_post
    host, port = serve(@echo_app)
    socket = TCPSocket.new(host, port)
    
    socket << "POST / HTTP/1.1\r\nHost: example.com\r\nTransfer-Encoding: chunked\r\n\r\n"
    socket << "3\r\nfoo\r\n"
    socket << "3\r\nbar\r\n"
    socket << "0\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: Keep-Alive\r\n\r\nfoobar",
      socket.sysread(1024))
  end
  
  def test_read_post_before_all_written
    chunks = []
    app = Proc.new do |env|
      while chunk = env["rack.input"].read(1024)
        chunks << chunk
      end
      [200, {"Content-Length" => "13"}, ["Hello world!\n"]]
    end
    host, port = serve(app)
    socket = TCPSocket.new(host, port)
    
    socket << "POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 9\r\n\r\n"
    wait_for_response
    socket << "foo"
    wait_for_response
    socket << "bar"
    wait_for_response
    socket << "baz"
    
    wait_for_response
    assert_equal(["foobarbaz"], chunks)
    
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
  end
  
  def test_100_continue
    host, port = serve(@echo_app)
    socket = TCPSocket.new(host, port)
    
    socket << "POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 4\r\nExpect: 100-continue\r\n\r\n"
    
    wait_for_response
    assert_equal("HTTP/1.1 100 Continue\r\n\r\n", socket.sysread(1024))
    
    socket << "test"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: Keep-Alive\r\n\r\ntest",
      socket.sysread(1024))
  end
  
  def test_close_on_eof
    host, port = serve(@echo_app)
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\n"
    socket.close_write
    
    wait_for_response
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_bad_request_on_malformed_request
    host, port = serve(@echo_app)
    socket = TCPSocket.new(host, port)
    
    socket << "not a http request"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n",
      socket.sysread(1024))
  end
  
  def test_accepts_new_connections_after_error
    host, port = serve(Proc.new do |env|
      raise if env["PATH_INFO"] == "/error"
      @hello_app.call(env)
    end)
    socket = TCPSocket.new(host, port)
    
    silence(STDERR) do
      socket << "GET /error HTTP/1.1\r\nHost: example.com\r\n\r\n"
    end
    
    assert_raise(EOFError) {socket.sysread(1)}
    
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
  end
  
  def test_graceful_shutdown
    host, port = "localhost", 8421
    app = Proc.new do |env|
      sleep 0.9
      @hello_app.call(env)
    end
    
    server = Tracks.new(app, :Host => host, :Port => port)
    thread = Thread.new {server.listen}
    sleep 0.001
    
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    sleep 0.001
    
    result = server.shutdown
    sleep 0.001
    
    assert_equal(true, thread.value)
    assert_raise(Errno::ECONNREFUSED) {TCPSocket.new(host, port)}
    assert(thread.stop?, "server thread should be stopped")
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket.sysread(1024))
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_forced_shutdown
    host, port = "localhost", 8421
    app = Proc.new do |env|
      sleep 0.1
      @hello_app.call(env)
    end
    
    server = Tracks.new(app, :Host => host, :Port => port, :shutdown_timeout => 0)
    thread = Thread.new {server.listen}
    sleep 0.001
    
    socket = TCPSocket.new(host, port)
    
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    sleep 0.001
    
    result = server.shutdown
    sleep 0.1
    
    assert_equal(false, thread.value)
    assert_raise(Errno::ECONNREFUSED) {TCPSocket.new(host, port)}
    assert(thread.stop?, "server thread should be stopped")
    assert_raise(EOFError) {socket.sysread(1)}
  end
  
  def test_restart
    host, port = "localhost", 8421
    app = Proc.new do |env|
      sleep 0.001
      @hello_app.call(env)
    end
    
    # startup
    server = Tracks.new(app, :Host => host, :Port => port)
    thread = Thread.new {server.listen}
    sleep 0.001
    
    # ensure we have a working server
    socket = TCPSocket.new(host, port)
    socket << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket.sysread(1024))
    
    # shutdown
    server.shutdown
    sleep 0.1
    
    # check it's stopped
    assert_raise(Errno::ECONNREFUSED) {TCPSocket.new(host, port)}
    assert(thread.stop?, "server thread should be stopped")
    
    # restart
    thread2 = Thread.new {server.listen}
    sleep 0.001
    
    # ensure we have a working server
    socket2 = TCPSocket.new(host, port)
    socket2 << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    wait_for_response
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\n\r\nHello world!\n",
      socket2.sysread(1024))
    
    # check graceful shutdown still works
    socket2 << "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    
    result = server.shutdown
    sleep 0.1
    
    assert_raise(Errno::ECONNREFUSED) {TCPSocket.new(host, port)}
    assert_equal(true, thread2.value)
    assert(thread2.stop?, "server thread should be stopped")
    assert_equal(
      "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello world!\n",
      socket2.sysread(1024))
    assert_raise(EOFError) {socket2.sysread(1)}
  end
  
  def test_shutdown_all
    host, port = "localhost", 8421
    
    server = Tracks.new(@hello_app, :Host => host, :Port => port)
    server2 = Tracks.new(@hello_app, :Host => host, :Port => port + 1)
    thread = Thread.new {server.listen}
    thread2 = Thread.new {server2.listen}
    
    sleep 0.01
    
    result = Tracks.shutdown
    sleep 0.01
    
    assert_equal(true, thread.value)
    assert_equal(true, thread2.value)
    assert_raise(Errno::ECONNREFUSED) {TCPSocket.new(host, port)}
    assert_raise(Errno::ECONNREFUSED) {TCPSocket.new(host, port + 1)}
    assert(thread.stop?, "server thread should be stopped")
    assert(thread2.stop?, "server thread should be stopped")
  end
  
end

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
  
end

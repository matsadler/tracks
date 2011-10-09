require 'tracks'
require 'openssl'

Rack::Handler.register('tracks_ssl', 'Tracks::SSL')

class Tracks
  class SSL < Tracks
    
    def initialize(app, options={})
      @ssl_context = OpenSSL::SSL::SSLContext.new
      cert = File.read(File.expand_path(options[:cert] || "ssl.crt"))
      @ssl_context.cert = OpenSSL::X509::Certificate.new(cert)
      key = File.read(File.expand_path(options[:key] || "ssl.key"))
      @ssl_context.key = OpenSSL::PKey::RSA.new(key)
      super
    end
    
    def on_connection(socket)
      ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, @ssl_context)
      ssl_socket.sync_close = true
      ssl_socket.accept
      super(ssl_socket)
    rescue OpenSSL::SSL::SSLError => e
      STDERR.puts("#{e.class}: #{e.message} #{e.backtrace.join("\n")}")
      ssl_socket.close
    end
    
  end
end

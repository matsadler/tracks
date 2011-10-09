require 'tracks'
require 'dnssd'

Rack::Handler.register('tracks_dnssd', 'Tracks::DNSSD')

class Tracks
  class DNSSD < Tracks
    
    def initialize(app, options={})
      @name = options[:name] || "Tracks"
      @service = options[:service] || "http"
      super
    end
    
    def listen(server=TCPServer.new(@host, @port))
      ::DNSSD.announce(server, @name, @service)
      super
    end
    
  end
end

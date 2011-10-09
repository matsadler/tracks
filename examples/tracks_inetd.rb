require 'tracks'

Rack::Handler.register('tracks_inetd', 'Tracks::INetD')

class Tracks
  module INetD
    
    def self.run(app, options={})
      STDERR.reopen(File.new("/dev/null", "w"))
      server = ::Tracks.new(app, options)
      
      server.on_connection(TCPSocket.for_fd(STDIN.fileno))
    end
    
  end
end

if $0 == __FILE__
  puts <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>tracks</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>#{ENV["PATH"]}</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>#{`which rackup`}</string>
    <string>-r#{__FILE__}</string>
    <string>-stracks_inetd</string>
    <string>#{File.expand_path(ARGV[0])}</string>
  </array>
  <key>Sockets</key>
  <dict>
    <key>http</key>
    <dict>
      <key>SockServiceName</key>
      <string>9292</string>
    </dict>
  </dict>
  <key>inetdCompatibility</key>
  <dict>
    <key>Wait</key>
    <false/>
  </dict>
</dict>
</plist>
  PLIST
end
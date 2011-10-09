require 'tracks'
require 'launch'

Rack::Handler.register('tracks_launch', 'Tracks::Launch')

class Tracks
  module Launch
    
    def self.run(app, options={})
      server = Tracks.new(app, options)
      sockets = ::Launch::Job.checkin.sockets["http"]
      if sockets.length == 1
        server.listen(sockets.first)
      else
        sockets.map {|sock| Thread.new {server.listen(sock)}}.each {|t| t.join}
      end
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
    <string>-stracks_launch</string>
    <string>#{File.expand_path(ARGV[0])}</string>
  </array>
  <key>ServiceIPC</key>
  <true/>
  <key>Sockets</key>
  <dict>
    <key>http</key>
    <dict>
      <key>SockServiceName</key>
      <string>9292</string>
    </dict>
  </dict>
</dict>
</plist>
  PLIST
end

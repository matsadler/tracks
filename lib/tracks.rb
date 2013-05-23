%W{socket http_tools rack rack/rewindable_input rack/utils}.each {|l| require l}

Rack::Handler.register('tracks', 'Tracks')

# Tracks is a bare-bones HTTP server that talks Rack and uses a thread per
# connection model of concurrency.
# 
# The simplest way to get up and running with Tracks is via rackup, in the same
# directory as your application's config.ru run
# 
#   rackup -rtracks -stracks
# 
# Alternately you can alter your config.ru, adding to the top
# 
#   require "tracks"
#   #\ --server tracks
# 
# If you need to start up Tracks from code, the simplest way to go is
# 
#   require "tracks"
#   Tracks.run(app, :host => host, :port => port)
# 
# Where app is a Rack app, responding to #call. The ::run method will block till
# the server quits. To stop all running Tracks servers in the current process
# call ::shutdown. You may want to setup a signal handler for this, like so
# 
#   trap(:INT) {Tracks.shutdown}
# 
# This will allow Tracks to gracefully shutdown when your program is quit with
# Ctrl-C. The signal handler must be setup before the call to ::run.
# 
# A slightly more generic version of the above looks like
# 
#   server = Tracks.new(app, :host => host, :port => port)
#   trap(:INT) {server.shutdown}
#   server.listen
# 
# To start a server listening on a Unix domain socket, an instance of
# UNIXServer can be given to #listen
# 
#   require "socket"
#   server = Tracks.new(app)
#   server.listen(UNIXServer.new("/tmp/tracks.sock"))
# 
# If you have an already accepted socket you can use Tracks to handle the
# connection like so
# 
#   server = Tracks.new(app)
#   server.on_connection(socket)
# 
# A specific use case for this would be an inetd handler, which would look like
# 
#   STDERR.reopen(File.new("/dev/null", "w"))
#   server = Tracks.new(app)
#   server.on_connection(TCPSocket.for_fd(STDIN.fileno))
# 
class Tracks
  %W{rack.input HTTP_VERSION REMOTE_ADDR Connection HTTP_CONNECTION Keep-Alive
    close HTTP/1.1 HTTP_EXPECT 100-continue SERVER_NAME SERVER_PORT
    Content-Length Transfer-Encoding}.map do |str|
    const_set(str.upcase.sub(/^[^A-Z]+/, "").gsub(/[^A-Z0-9]/, "_"), str.freeze)
  end
  ENV_CONSTANTS = {"rack.multithread" => true} # :nodoc:
  include HTTPTools::Builder
  
  @running = []
  class << self
    # class accessor, array of currently running instances
    attr_accessor :running
  end
  
  # Tracks::Input is used to defer reading of the input stream. It is used
  # internally to Tracks, and should not need to be created outside of Tracks.
  # 
  # Tracks::Input is not rewindable, so will always come wrapped by a
  # Rack::RewindableInput. The #read method conforms to the Rack input spec for
  # #read.
  # 
  # On initialisation the Tracks::Input instance is given an object which it
  # will use to notify it's creator when input is required. This will be done
  # by calling the #call method on the passed object. This call method should
  # block until after a chunk of input has been fed to the Tracks::Input
  # instance's #recieve_chunk method.
  # 
  class Input
    # set true when the end of the stream has been read into the internal buffer
    attr_accessor :finished
    
    # :call-seq: Input.new(reader) -> input
    # 
    # Create a new Input instance.
    # 
    def initialize(reader)
      @reader = reader
      reset
    end
    
    # :call-seq: input.read([length[, buffer]])
    # 
    # Read at most length bytes from the input stream.
    # 
    # Conforms to the Rack spec for the input stream's #read method:
    # 
    # If given, length must be an non-negative Integer (>= 0) or nil, and
    # buffer must be a String and may not be nil. If length is given and not
    # nil, then this method reads at most length bytes from the input stream.
    # If length is not given or nil, then this method reads all data until EOF.
    # When EOF is reached, this method returns nil if length is given and not
    # nil, or "" if length is not given or is nil. If buffer is given, then the
    # read data will be placed into buffer instead of a newly created String
    # object.
    # 
    def read(length=nil, output="")
      @on_initial_read.call if @on_initial_read && !@started
      @started = true
      
      if length && (@buffer || fill_buffer)
        fill_buffer until @buffer.length >= length || @finished
        output.replace(@buffer.slice!(0, length))
        @buffer = nil if @buffer.empty?
      elsif length
        output = nil
      elsif !@finished
        fill_buffer until @finished
        output.replace(@buffer || "")
        @buffer = nil
      end
      output
    end
    
    # :call-seq: input.recieve_chunk(string) -> string
    # 
    # Append string to the internal buffer.
    # 
    def recieve_chunk(chunk)
      if @buffer then @buffer << chunk else @buffer = chunk.dup end
    end
    
    # :call-seq: input.first_read { block } -> block
    # 
    # Setup a callback to be executed on when #read is first called. Only one
    # callback can be set, with subsequent calls to this method overriding the
    # previous. Used internally to Tracks for automatic 100-continue support.
    # 
    def first_read(&block)
      @on_initial_read = block
    end
    
    # :call-seq: input.reset -> nil
    # 
    # Reset input, allowing it to be reused.
    # 
    def reset
      @started = false
      @finished = false
      @buffer = nil
    end
    
    private
    def fill_buffer
      @reader.call unless @finished
      @buffer
    end
  end
  
  # :call-seq: Tracks.new(rack_app[, options]) -> server
  # 
  # Create a new Tracks server. rack_app should be a rack application,
  # responding to #call. options should be a hash, with the following optional
  # keys, as symbols
  # 
  # [:host]             the host to listen on, defaults to 0.0.0.0
  # [:port]             the port to listen on, defaults to 9292
  # [:read_timeout]     the maximum amount of time, in seconds, to wait on idle
  #                     connections, defaults to 30
  # [:shutdown_timeout] the maximum amount of time, in seconds, to wait for
  #                     in process requests to complete when signalled to shut
  #                     down, defaults to 30
  # 
  def initialize(app, options={})
    @host = options[:host] || options[:Host] || "0.0.0.0"
    @port = (options[:port] || options[:Port] || "9292").to_s
    @read_timeout = options[:read_timeout] || 30
    @shutdown_timeout = options[:shutdown_timeout] || 30
    @app = app
  end
  
  # :call-seq: Tracks.run(rack_app[, options]) -> nil
  # 
  # Equivalent to Tracks.new(rack_app, options).listen
  # 
  def self.run(app, options={})
    new(app, options).listen
  end
  
  # :call-seq: Tracks.shutdown -> nil
  # 
  # Signal all running Tracks servers to shutdown.
  # 
  def self.shutdown
    running.dup.each {|s| s.shutdown} && nil
  end
  
  # :call-seq: server.shutdown -> nil
  # 
  # Signal the server to shut down.
  # 
  def shutdown
    @shutdown = true
    self.class.running.delete(self) && nil
  end
  
  # :call-seq: server.listen([socket_server]) -> bool
  # 
  # Start listening for/accepting connections on socket_server. socket_server
  # defaults to a TCP server listening on the host and port supplied to ::new.
  # 
  # An alternate socket server can be supplied as an argument, such as an
  # instance of UNIXServer to listen on a unix domain socket.
  # 
  # This method will block until #shutdown is called. The socket_server will
  # be closed when this method returns.
  # 
  # A return value of false indicates there were threads left running after
  # shutdown_timeout had expired which were forcibly killed. This may leave
  # resources in an inconsistant state, and it is advised you exit the process
  # in this case (likely what you were planning anyway).
  # 
  def listen(server=TCPServer.new(@host, @port))
    @shutdown = false
    server.listen(1024) if server.respond_to?(:listen)
    @port, @host = server.addr[1,2].map{|e| e.to_s} if server.respond_to?(:addr)
    servers = [server]
    threads = ThreadGroup.new
    self.class.running << self
    puts "Tracks HTTP server available at #{@host}:#{@port}"
    if select(servers, nil, nil, 0.1)
      threads.add(Thread.new(server.accept) {|sock| on_connection(sock)})
    end until @shutdown
    server.close
    wait = @shutdown_timeout
    wait -= sleep 1 until threads.list.empty? || wait <= 0
    threads.list.each {|thread| thread.kill}.empty?
  end
  
  # :call-seq: server.on_connection(socket) -> nil
  # 
  # Handle HTTP messages on socket, dispatching them to the rack_app supplied to
  # ::new.
  # 
  # This method will return when socket has reached EOF or has been idle for
  # the read_timeout supplied to ::new. The socket will be closed when this
  # method returns.
  # 
  # Errors encountered in this method will be printed to stderr, but not raised.
  # 
  def on_connection(socket)
    parser = HTTPTools::Parser.new
    buffer = ""
    sockets = [socket]
    idle = false
    reader = Proc.new do
      wait = @read_timeout
      begin
        return if idle && @shutdown
        readable, = select(sockets, nil, nil, 0.1)
        wait - 0.1
      end until readable || wait < 0
      return unless readable
      idle = false
      begin
        socket.sysread(16384, buffer)
        parser << buffer
      rescue HTTPTools::ParseError
        socket << response(400, CONNECTION => CLOSE)
        return
      rescue EOFError
        return
      end
    end
    input = Input.new(reader)
    parser.on(:stream) {|chunk| input.recieve_chunk(chunk)}
    parser.on(:finish) {input.finished = true}
    
    remote_family, remote_port, remote_host, remote_addr = socket.peeraddr
    while true
      reader.call until parser.header?
      env = {SERVER_NAME => @host, SERVER_PORT => @port}.merge!(parser.env
        ).merge!(HTTP_VERSION => parser.version, REMOTE_ADDR => remote_addr,
        RACK_INPUT => Rack::RewindableInput.new(input)).merge!(ENV_CONSTANTS)
      input.first_read {socket << response(100)} if env[HTTP_EXPECT] == CONTINUE
      
      status, header, body = @app.call(env)
      
      header = Rack::Utils::HeaderHash.new(header)
      connection_header = header[CONNECTION] || env[HTTP_CONNECTION]
      keep_alive = ((parser.version.casecmp(HTTP_1_1) == 0 &&
        (!connection_header || connection_header.casecmp(CLOSE) != 0)) ||
        (connection_header && connection_header.casecmp(KEEP_ALIVE) == 0)) &&
        !@shutdown && (header.key?(CONTENT_LENGTH) ||
        header.key?(TRANSFER_ENCODING) || HTTPTools::NO_BODY[status.to_i])
      header[CONNECTION] = keep_alive ? KEEP_ALIVE : CLOSE
      
      socket << response(status, header)
      body.each {|chunk| socket << chunk}
      body.close if body.respond_to?(:close)
      
      if keep_alive && !@shutdown
        reader.call until parser.finished?
        input.reset
        remainder = parser.rest.lstrip
        parser.reset << remainder
        idle = true
      else
        break
      end
    end
    
  rescue StandardError, LoadError, SyntaxError => e
    STDERR.puts("#{e.class}: #{e.message} #{e.backtrace.join("\n")}")
  ensure
    socket.close
  end
  
end

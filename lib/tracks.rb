%W{socket http_tools rack rack/rewindable_input}.each {|lib| require lib}

Rack::Handler.register('tracks', 'Tracks')

class Tracks
  %W{rack.input HTTP_VERSION REMOTE_ADDR Connection Keep-Alive close HTTP/1.1
    HTTP_EXPECT 100-continue SERVER_NAME SERVER_PORT Content-Length
    Transfer-Encoding}.map do |str|
    const_set(str.upcase.sub(/^[^A-Z]+/, "").gsub(/[^A-Z0-9]/, "_"), str.freeze)
  end
  ENV_CONSTANTS = {"rack.multithread" => true}
  include HTTPTools::Builder
  
  class Input
    attr_accessor :finished
    
    def initialize(reader)
      @reader = reader
      reset
    end
    
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
    
    def recieve_chunk(chunk)
      if @buffer then @buffer << chunk else @buffer = chunk end
    end
    
    def first_read(&block)
      @on_initial_read = block
    end
    
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
  
  def initialize(app, options={})
    @host = options[:host] || options[:Host] || "0.0.0.0"
    @port = (options[:port] || options[:Port] || "9292").to_s
    @read_timeout = options[:read_timeout] || 30
    @app = app
    @shutdown_signal, @signal_shutdown = IO.pipe
    @threads = ThreadGroup.new
  end
  
  def self.run(app, options={})
    new(app, options).listen
  end
  
  def shutdown(wait=30)
    @shutdown = true
    @signal_shutdown << "x"
    wait -= sleep 1 until @threads.list.empty? || wait <= 0
    @threads.list.each {|thread| thread.kill}.empty?
  end
  
  def listen(server=TCPServer.new(@host, @port))
    @shutdown = false
    server.listen(1024) if server.respond_to?(:listen)
    @port, @host = server.addr[1,2].map{|e| e.to_s} if server.respond_to?(:addr)
    servers = [server, @shutdown_signal]
    puts "Tracks HTTP server available at #{@host}:#{@port}"
    while select(servers, nil, nil) && !@shutdown
      @threads.add(Thread.new(server.accept) {|sock| on_connection(sock)})
    end
    @shutdown_signal.sysread(1) && nil
  ensure
    server.close
  end
  
  def on_connection(socket)
    parser = HTTPTools::Parser.new
    buffer = ""
    sockets = [socket]
    reader = Proc.new do
      readable, = select(sockets, nil, nil, @read_timeout)
      return unless readable
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
      
      connection_header = header[CONNECTION] || parser.header[CONNECTION]
      keep_alive = (parser.version == HTTP_1_1 && connection_header != CLOSE ||
        connection_header == KEEP_ALIVE) && !@shutdown &&
        (header.key?(CONTENT_LENGTH) || header.key?(TRANSFER_ENCODING))
      header[CONNECTION] = keep_alive ? KEEP_ALIVE : CLOSE
      
      socket << response(status, header)
      body.each {|chunk| socket << chunk}
      body.close if body.respond_to?(:close)
      
      if keep_alive
        reader.call until parser.finished?
        input.reset
        remainder = parser.rest.lstrip
        parser.reset << remainder
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

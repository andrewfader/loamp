# frozen_string_literal: true

require 'socket'

# A real HTTP server, on a real socket, for the duration of one example.
#
# The network layer is worth testing for real: redirects, status codes, headers
# and JSON bodies are exactly where it can be wrong, and none of that is
# exercised by stubbing Net::HTTP out. This serves canned replies from
# 127.0.0.1 on a port the kernel picks, so specs stay offline and parallel-safe
# without pulling in a stubbing library.
#
# Every request that arrives is recorded, so a spec can also assert on what was
# sent — that the User-Agent MusicBrainz insists on was actually there, say.
class StubHttpServer
  Request = Struct.new(:method, :path, :query, :headers, keyword_init: true)

  # Sent when a spec asked for a path that was never routed.
  NOT_FOUND = [404, {}, 'not found'].freeze

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @routes = {}
    @requests = []
    @mutex = Mutex.new
    @thread = Thread.new { serve }
  end

  def port = @server.addr[1]

  def url_for(path) = "http://127.0.0.1:#{port}#{path}"

  # Routes a path, either to a fixed reply or to a block that builds one from
  # the request. The block form is what a redirect chain or a "fail once, then
  # succeed" case needs.
  def on(path, status: 200, body: '', headers: {}, &block)
    @routes[path] = block || ->(_request) { [status, headers, body] }
  end

  def requests
    @mutex.synchronize { @requests.dup }
  end

  def stop
    @thread&.kill
    @thread&.join
    @server.close unless @server.closed?
  end

  private

  def serve
    loop do
      handle(@server.accept)
    rescue IOError, Errno::EBADF, Errno::ECONNRESET, Errno::EPIPE
      break
    end
  end

  def handle(socket)
    request = read_request(socket)
    return unless request

    @mutex.synchronize { @requests << request }
    status, headers, body = reply_to(request)
    write_response(socket, status, headers, body)
  rescue Errno::EPIPE, Errno::ECONNRESET
    nil
  ensure
    socket.close unless socket.closed?
  end

  def reply_to(request)
    route = @routes[request.path]
    route ? route.call(request) : NOT_FOUND
  end

  def read_request(socket)
    line = socket.gets
    return nil unless line

    method, target, = line.split
    path, query = target.to_s.split('?', 2)

    Request.new(method: method, path: path, query: query.to_s, headers: read_headers(socket))
  end

  def read_headers(socket)
    headers = {}

    while (line = socket.gets)
      line = line.chomp
      break if line.empty?

      name, value = line.split(':', 2)
      headers[name.to_s.downcase] = value.to_s.strip
    end

    headers
  end

  def write_response(socket, status, headers, body)
    body = body.to_s
    # Connection: close, so net/http reads to the end and stops rather than
    # holding the socket open waiting for a second request that never comes.
    lines = ["HTTP/1.1 #{status} #{status_text(status)}",
             "Content-Length: #{body.bytesize}",
             'Connection: close']
    headers.each { |name, value| lines << "#{name}: #{value}" }

    socket.write("#{lines.join("\r\n")}\r\n\r\n")
    socket.write(body)
  end

  def status_text(status)
    case status
    when 200 then 'OK'
    when 206 then 'Partial Content'
    when 301 then 'Moved Permanently'
    when 302 then 'Found'
    when 307 then 'Temporary Redirect'
    when 404 then 'Not Found'
    when 416 then 'Range Not Satisfiable'
    when 503 then 'Service Unavailable'
    else 'Status'
    end
  end
end

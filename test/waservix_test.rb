# frozen_string_literal: true

require 'minitest/autorun'
require 'socket'
require 'json'
require 'waservix'

# Tiny HTTP server so tests need no extra gems.
class FakeServer
  attr_reader :port, :last

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @last = nil
    @thread = Thread.new { loop { handle(@server.accept) } }
  end

  def handle(sock)
    line = sock.gets or return
    method, path, = line.split(' ')
    headers = {}
    while (h = sock.gets) && h != "\r\n"
      k, v = h.split(':', 2)
      headers[k.downcase] = v.strip
    end
    body = headers['content-length'] ? sock.read(headers['content-length'].to_i) : ''
    @last = { method: method, path: path, headers: headers, body: body.empty? ? nil : JSON.parse(body) }
    status, reply = if path.start_with?('/down')
                      [503, '{"success":false,"message":"Device reconnecting"}']
                    else
                      [200, '{"success":true,"data":{"msgId":58213,"status":"in_progress"}}']
                    end
    sock.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
  ensure
    sock&.close
  end
end

class WAservixTest < Minitest::Test
  SERVER = FakeServer.new

  def client(prefix = '')
    WAservix::Client.new(api_key: 'wpk_test', base_url: "http://127.0.0.1:#{SERVER.port}#{prefix}")
  end

  def test_send_text
    assert_equal 58_213, client.send_text('+1555', 'hi')['msgId']
    last = SERVER.last
    assert_equal ['POST', '/send-message'], [last[:method], last[:path]]
    assert_equal 'Bearer wpk_test', last[:headers]['authorization']
    assert_equal({ 'to' => '+1555', 'text' => 'hi' }, last[:body])
  end

  def test_media_and_paths
    c = client
    c.send_image('+1', 'https://x/y.jpg')
    assert_equal({ 'to' => '+1', 'imageUrl' => 'https://x/y.jpg' }, SERVER.last[:body])
    c.send_document('+1', 'https://x/a.pdf', file_name: 'a.pdf', caption: 'c')
    assert_equal 'a.pdf', SERVER.last[:body]['fileName']
    c.get_message_info(5)
    assert_equal '/messages/5/info', SERVER.last[:path]
    c.edit_message(5, 't')
    assert_equal ['PUT', { 'text' => 't' }], [SERVER.last[:method], SERVER.last[:body]]
    c.on_whatsapp('+1555')
    assert_equal '/on-whatsapp/%2B1555', SERVER.last[:path]
    c.get_group_metadata('1203@g.us')
    assert_equal '/groups/1203%40g.us/metadata', SERVER.last[:path]
    c.connect_session(3)
    assert_equal({ 'method' => 'qr' }, SERVER.last[:body])
  end

  def test_errors
    err = assert_raises(WAservix::Error) { client('/down').get_status }
    assert_equal 503, err.status
    assert_equal 'Device reconnecting', err.message
    assert_raises(ArgumentError) { client.send_text('', 'x') }
  end

  def test_webhook
    assert WAservix.verify_webhook('abc', 'abc')
    refute WAservix.verify_webhook('abd', 'abc')
    refute WAservix.verify_webhook(nil, 'abc')
  end
end

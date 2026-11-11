# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

# Ruby client for the WAservix WhatsApp API Gateway.
#
#   wa = WAservix::Client.new(api_key: ENV['WASERVIX_KEY'])
#   wa.send_text('+15551234567', 'Hello Aline, your order is ready')
#
# Docs: https://tekservix.com/waservix/docs/
module WAservix
  VERSION = '1.0.1'
  DEFAULT_BASE_URL = 'https://tekservix.com/waservix/api'

  # Raised when the API answers with an error. A 503 means the device is reconnecting.
  class Error < StandardError
    attr_reader :status, :errors, :body, :retry_after

    def initialize(message, status: nil, errors: nil, body: nil, retry_after: nil)
      super(message)
      @status = status
      @errors = errors
      @body = body
      @retry_after = retry_after
    end
  end

  class Client
    attr_reader :base_url

    # api_key: device API key (wpk_...) or a personal access token for session management.
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: 30)
      raise ArgumentError, 'WAservix: api_key is required (Devices -> API key in the WAservix dashboard)' if api_key.nil? || api_key.empty?

      @api_key = api_key
      @base_url = base_url.sub(%r{/+\z}, '')
      @timeout = timeout
    end

    # Call any documented endpoint, e.g. request(:get, '/groups'). Returns the `data` field.
    def request(method, path, body = nil)
      uri = URI(@base_url + path)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method.to_s.downcase.to_sym)
      req = klass.new(uri)
      req['Authorization'] = "Bearer #{@api_key}"
      req['Accept'] = 'application/json'
      req['User-Agent'] = "waservix-ruby/#{VERSION}"
      unless body.nil?
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                open_timeout: @timeout, read_timeout: @timeout) { |http| http.request(req) }
      status = res.code.to_i
      text = res.body.to_s
      json = begin
        text.empty? ? nil : JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      if status >= 400 || (json.is_a?(Hash) && json['success'] == false)
        retry_after = res['Retry-After']
        raise Error.new((json.is_a?(Hash) && json['message']) || "HTTP #{status}",
                        status: status,
                        errors: json.is_a?(Hash) ? json['errors'] : nil,
                        body: json || text,
                        retry_after: retry_after && Float(retry_after, exception: false))
      end
      json.is_a?(Hash) && json.key?('data') ? json['data'] : json
    end

    # Send any message type to a number or group JID (...@g.us). Fields use the API names:
    # text, imageUrl, videoUrl, audioUrl, documentUrl, fileName, stickerUrl, contact, location,
    # poll, replyTo, mentions, viewOnce. Returns { 'msgId' => ..., 'jid' => ..., 'status' => 'in_progress' }.
    def send_message(to, **fields)
      raise ArgumentError, 'send_message: "to" is required (international number or group JID)' if to.nil? || to.empty?

      request(:post, '/send-message', { to: to }.merge(fields.reject { |_, v| v.nil? }))
    end

    def send_text(to, text)
      send_message(to, text: text)
    end

    def send_image(to, image_url, caption: nil)
      send_message(to, imageUrl: image_url, text: caption)
    end

    def send_document(to, document_url, file_name: nil, caption: nil)
      send_message(to, documentUrl: document_url, fileName: file_name, text: caption)
    end

    # Status: queued, sent, delivered, read, played or failed.
    def get_message_info(msg_id)
      request(:get, "/messages/#{esc(msg_id)}/info")
    end

    # Edit one of your own text messages (about 15 minutes after sending).
    def edit_message(msg_id, text)
      request(:put, "/messages/#{esc(msg_id)}", { text: text })
    end

    def delete_message(msg_id)
      request(:delete, "/messages/#{esc(msg_id)}")
    end

    def resend_message(msg_id)
      request(:post, "/messages/#{esc(msg_id)}/resend")
    end

    # Is this number on WhatsApp? Returns { 'exists' => true/false, 'jid' => ... }.
    def on_whatsapp(phone)
      request(:get, "/on-whatsapp/#{esc(phone)}")
    end

    # connected, connecting, need_scan, disconnected, logged_out or expired.
    def get_status
      request(:get, '/status')
    end

    def get_user
      request(:get, '/user')
    end

    def list_contacts
      request(:get, '/contacts')
    end

    def get_contact(phone)
      request(:get, "/contacts/#{esc(phone)}")
    end

    def save_contact(phone, name)
      request(:put, '/contacts', { phone: phone, name: name })
    end

    def list_groups
      request(:get, '/groups')
    end

    def get_group_metadata(group_jid)
      request(:get, "/groups/#{esc(group_jid)}/metadata")
    end

    # Session management (needs a personal access token, not a device key).
    def list_sessions
      request(:get, '/whatsapp-sessions')
    end

    def get_session(id)
      request(:get, "/whatsapp-sessions/#{esc(id)}")
    end

    def create_session(**params)
      request(:post, '/whatsapp-sessions', params)
    end

    # method: 'qr', or 'code' with phone: for pairing codes.
    def connect_session(id, method: 'qr', phone: nil)
      body = { method: method }
      body[:phone] = phone if phone
      request(:post, "/whatsapp-sessions/#{esc(id)}/connect", body)
    end

    def get_session_qr_code(id)
      request(:get, "/whatsapp-sessions/#{esc(id)}/qrcode")
    end

    private

    def esc(value)
      URI.encode_www_form_component(value.to_s).gsub('+', '%20')
    end
  end

  # Constant-time check of the X-Webhook-Signature header against your device's webhook secret.
  def self.verify_webhook(signature, secret)
    return false if signature.nil? || signature.empty? || secret.nil? || secret.empty?
    secure_compare(signature.to_s, secret.to_s)
  end

  # Constant-time string comparison (works on every Ruby version).
  def self.secure_compare(a, b)
    return false unless a.bytesize == b.bytesize

    diff = 0
    a.bytes.zip(b.bytes) { |x, y| diff |= x ^ y }
    diff.zero?
  end
  private_class_method :secure_compare
end

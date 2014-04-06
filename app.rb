require 'rubygems'
require 'sinatra/base'
require 'sinatra/param'
require 'redis'
require 'json'
require 'sidekiq'
require 'net/smtp'
require_relative 'mailer'

module Baggage
  DEFAULT_EXPIRES = 7
  MIN_EXPIRES = 1
  MAX_EXPIRES = 365
  ID_BYTES = 16
  TOKEN_BYTES = 32
  ID_LENGTH = ID_BYTES * 2
  TOKEN_LENGTH = TOKEN_BYTES * 2
end

module Baggage
  class RedisDataStore
    def initialize(args = {})
      @data_store = Redis.new
    end

    def read()
      @doc = JSON.parse(@data_store.get(@id), :symbolize_names => true)
      if not @doc
        raise 'could not read'
      end
    end

    def set_expiry()
      expires_sec = @doc[:expires] * 24 * 60 * 60
      if not @data_store.expire(@id, expires_sec)
        raise 'could not set expiry'
      end
    end

    def write()
      if not @data_store.set(@id, @doc.to_json)
        raise 'could not write'
      end
      set_expiry
    end

    def delete()
      if not @data_store.del(@id)
        raise 'could not delete'
      end
    end
  end
end

module Baggage
  class Subscriber < RedisDataStore

    def initialize()
      @doc = {}
      @id = nil
      super
    end

    def generate_id()
      SecureRandom.hex(Baggage::ID_BYTES)
    end

    def generate_token()
      SecureRandom.hex(Baggage::TOKEN_BYTES)
    end

    def generate_tokens()
      @doc[:email_token] = generate_token
      @doc[:admin_token] = generate_token
    end

    def send_tokens(message)
      from = 'Baggage.io <no-reply@baggage.io>'
      subject = 'New Baggage.io subscription'
      body = <<BODY_END
#{message}

id:              #{@id}
email token:     #{@doc[:email_token]}
admin token:     #{@doc[:admin_token]}

rotate tokens:   http://api.baggage.io/rotate/#{@id}?token=#{@doc[:admin_token]}
unsubscribe:     http://api.baggage.io/unsubscribe/#{@id}?token=#{@doc[:admin_token]}

Your subscription will expire after #{@doc[:expires]} days of inactivity.

send a message:

http://api.baggage.io/send/#{@id}?token=#{@doc[:email_token]}&subject=hello&body=world

Regards,
baggage.io
BODY_END

        BaggageMailer.perform_async('to' => @doc[:email], 'from' => from, 'subject' => subject, 'body' => body)
    end

    def send_unsubscribed()
      from = 'Baggage.io <no-reply@baggage.io>'
      subject = "Baggage.io #{@id} unsubscribed"
      body = <<BODY_END
Hi,

ID #{@id} has been unsubscribed. Thank you.

Regards,
baggage.io
BODY_END

        BaggageMailer.perform_async('to' => @doc[:email], 'from' => from, 'subject' => subject, 'body' => body)
    end

    def subscribe(args = {})
      @doc = args
      @id = generate_id
      generate_tokens
      write
      send_tokens('Your new subscription:')
    end

    def rotate(args = {})
      @id = args[:id]
      read
      if @doc[:admin_token] == args[:token]
        generate_tokens
        write
        send_tokens('Tokens have been rotated. The new values are:')
      else
        raise 'invalid token'
      end
    end

    def unsubscribe(args = {})
      @id = args[:id]
      read
      if @doc[:admin_token] == args[:token]
        delete
        send_unsubscribed
      else
        raise 'invalid token'
      end
    end

    def send(args = {})
      @id = args[:id]
      read
      if @doc[:email_token] == args[:token]
        set_expiry
        BaggageMailer.perform_async('to' => @doc[:email], 'from' => args[:from], 'subject' => args[:subject], 'body' => args[:body])
      else
        raise 'invalid token'
      end
    end
  end
end

module Baggage
  class App < Sinatra::Base
    helpers Sinatra::Param

    before do
      content_type :json
    end

    # GET /subscribe/user@domain
    # GET /subscribe/user@domain?expires=1
    get '/subscribe/:email' do
      param :email,     String, format: /^[a-zA-Z0-9\.\_\+\@\(\)]+$/, required: true
      param :expires,   Integer, min: Baggage::MIN_EXPIRES, max: Baggage::MAX_EXPIRES, default: Baggage::DEFAULT_EXPIRES
      begin
        s = Subscriber.new
        s.subscribe(:email => params[:email], :expires => params[:expires])
        { :message => 'subscription sent' }.to_json
      rescue Exception => e
        halt 400, { :message => e.message }.to_json
      end
    end

    # GET /rotate/xxx?token=yyy
    # GET /rotate/xxx?token=yyy&expires=1
    get '/rotate/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true
      param :expires,   Integer, min: Baggage::MIN_EXPIRES, max: Baggage::MAX_EXPIRES, default: Baggage::DEFAULT_EXPIRES
      begin
        s = Subscriber.new
        s.rotate(:id => params[:id], :token => params[:token], :expires => params[:expires])
        { :message => 'rotated' }.to_json
      rescue Exception => e
        halt 400, { :message => e.message }.to_json
      end
    end

    # GET /unsubscribe/xxx?token=yyy
    get '/unsubscribe/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true
      begin
        s = Subscriber.new
        s.unsubscribe(:id => params[:id], :token => params[:token])
        { :message => 'unsubscribed' }.to_json
      rescue Exception => e
        halt 400, { :message => e.message }.to_json
      end
    end

    # GET /send/xxx?token=yyy&subject=abc&message=def
    get '/send/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true
      param :subject,   String, required: true
      param :body,      String, required: true
      param :from,      String, default: 'no-reply@baggage.io'

      begin
        s = Subscriber.new
        s.send(:id => params[:id], :token => params[:token], :subject => params[:subject], :body => params[:body], :from => params[:from])
        { :message => 'sent' }.to_json
      rescue Exception => e
        halt 400, { :message => e.message }.to_json
      end
    end

    not_found do
      halt 404, '{ "message": "not found" }'
    end

    run! if app_file == $0
  end
end

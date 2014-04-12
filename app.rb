require 'rubygems'
require 'sinatra/base'
require 'sinatra/param'
require 'sinatra/respond_with'
require 'redis'
require 'json'
require 'sidekiq'
require 'time'
require_relative 'mailer'
require 'newrelic_rpm'
require 'gyoku'
require 'yaml'

module Baggage
  DEFAULT_EXPIRES = 7
  MIN_EXPIRES = 1
  MAX_EXPIRES = 365
  ID_BYTES = 16
  TOKEN_BYTES = 32
  ID_LENGTH = ID_BYTES * 2
  TOKEN_LENGTH = TOKEN_BYTES * 2
  MAIL_FROM_NAME = 'baggage.io'
  MAIL_FROM_ADDR = '<no-reply@baggage.io>'
  NAME_LENGTH = 64
end

module Baggage
  class Response
    def self.text(resp = {})
      self.yaml(resp)
    end

    def self.yaml(resp = {})
      resp.to_yaml
    end

    def self.json(resp = {})
      resp.to_json
    end

    def self.xml(resp = {})
      Gyoku.xml(resp)
    end

  end
end

module Baggage
  class RedisDataStore
    def initialize(args = {})
      @data_store = Redis.new
    end

    def exists?(id)
      @data_store.exists(id) == 1
    end

    def read()
      data = @data_store.get(@id)
      if not data
        raise 'could not read'
      end

      @doc = JSON.parse(data, :symbolize_names => true)
      if not @doc
        raise 'could not parse'
      end
    end

    def set_expiry()
      @doc[:expires] = DEFAULT_EXPIRES unless @doc.has_key?(:expires)
      expires_sec = @doc[:expires] * 24 * 60 * 60
      if not @data_store.expire(@id, expires_sec)
        raise 'could not set expiry'
      end
    end

    def get_ttl()
      @data_store.ttl(@id)
    end

    def write()
      @doc[:updated] = Time.now
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

    attr_accessor :id, :doc

    def initialize()
      @doc = {}
      @id = nil
      super
    end

    def generate_id()
      10.times do
        id = SecureRandom.hex(Baggage::ID_BYTES)
        if not exists?(id)
          return id
        end
      end

      raise 'could not generate unique id'
    end

    def generate_token()
      SecureRandom.hex(Baggage::TOKEN_BYTES)
    end

    def generate_tokens()
      @doc[:email_token] = generate_token
      @doc[:admin_token] = generate_token
    end

    def unsubscribe_url
      "https://api.baggage.io/unsubscribe/#{@id}?token="
    end

    def send_tokens(subject, message)
      from = "#{MAIL_FROM_NAME} #{MAIL_FROM_ADDR}"
      body = <<BODY_END
Hi,

#{message}

    id:              #{@id}
    email token:     #{@doc[:email_token]}
    admin token:     #{@doc[:admin_token]}

Use to the email token to send emails and use the admin token to get stats, rotate the tokens, or unsubscribe. 

Please keep the admin token safe.


Send a message:

https://api.baggage.io/send/#{@id}?token=#{@doc[:email_token]}&subject=hello&body=world


Retrieve subscription statistics:

https://api.baggage.io/stats/#{@id}?token=#{@doc[:admin_token]}


To change your tokens:

https://api.baggage.io/rotate/#{@id}?token=#{@doc[:admin_token]}


To unsubscribe:

https://api.baggage.io/unsubscribe/#{@id}?token=#{@doc[:admin_token]}


Installing the baggage command line tool:

curl -sL -o baggage http://tool.baggage.io && chmod +x baggage


For normal or system users add the id and email token:

touch ~/.baggage && chmod 0600 ~/.baggage && cat <<EOF > ~/.baggage
BAGGAGE_ID=#{@id}
BAGGAGE_EMAIL_TOKEN=#{@doc[:email_token]}
EOF

For admins you can also add the admin token to the .baggage file:

BAGGAGE_ADMIN_TOKEN=#{@doc[:admin_token]}


Use the tool:

./baggage help


Your subscription will expire after #{@doc[:expires]} days of inactivity.

Regards,
baggage.io

--
To report abuse, please email abuse@baggage.io
For all other issues, email help@baggage.io
BODY_END

        BaggageMailer.perform_async('ip' => @doc[:last_admin_ip], 
                                    'to' => @doc[:email], 
                                    'from' => from, 
                                    'subject' => subject, 
                                    'body' => body,
                                    'unsubscribe' => unsubscribe_url)
    end

    def send_unsubscribed()
      from = "#{MAIL_FROM_NAME} #{MAIL_FROM_ADDR}"
      subject = "baggage.io #{@id} unsubscribed"
      body = <<BODY_END
Hi,

#{@id} has been unsubscribed. Thank you.

Regards,
baggage.io

--
To report abuse, please email abuse@baggage.io
For all other issues, email help@baggage.io
BODY_END

        BaggageMailer.perform_async('ip' => @doc[:last_admin_ip], 
                                    'to' => @doc[:email], 
                                    'from' => from, 
                                    'subject' => subject, 
                                    'body' => body,
                                    'unsubscribe' => unsubscribe_url)
    end

    def subscribe(args = {})
      @doc = args
      @id = generate_id
      @doc[:sent_count] = 0
      @doc[:created] = Time.now
      @doc[:subscriber_ip] = @doc[:last_admin_ip]
      generate_tokens
      write

      send_tokens("New baggage.io subscription", "Your new subscription:")
    end

    def update(args = {})
      @id = args[:id]
      read
      if @doc[:admin_token] == args[:token]
        @doc[:name] = args[:name] unless args[:name].nil?
        @doc[:expires] = args[:expires] unless args[:expires].nil?
        write
      else
        raise 'invalid token'
      end
    end

    def stats(args = {})
      @id = args[:id]
      read
      if @doc[:admin_token] == args[:token]
        stats = {}
        stats[:id] = @id
        %w[ name email created updated sent_count subscriber_ip last_admin_ip last_sender_ip ].each do |key|
          stats[key.to_sym] = @doc[key.to_sym]
        end
        stats[:ttl] = get_ttl
        return stats
      else
        raise 'invalid token'
      end
    end

    def rotate(args = {})
      @id = args[:id]
      read
      if @doc[:admin_token] == args[:token]
        generate_tokens
        write
        send_tokens('Your new baggage.io tokens', 'Your tokens have been rotated. The new values are:')
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
        @doc[:sent_count] += 1
        @doc[:last_sender_ip] = args[:last_sender_ip]
        write
        BaggageMailer.perform_async('ip' => @doc[:last_sender_ip],
                                    'to' => @doc[:email],
                                    'from' => "#{args[:from]} #{MAIL_FROM_ADDR}",
                                    'subject' => args[:subject], 
                                    'body' => args[:body],
                                    'unsubscribe' => unsubscribe_url)
      else
        raise 'invalid token'
      end
    end
  end
end

module Baggage
  class App < Sinatra::Base
    helpers Sinatra::Param
    register Sinatra::RespondWith

    respond_to :html, :json, :xml, :text, :yaml
    set :default_content, :json

    def return_response(response)
      respond_to do |f|
        f.html { Baggage::Response.json(response) }
        f.txt  { Baggage::Response.text(response) }
        f.json { Baggage::Response.json(response) }
        f.xml  { Baggage::Response.xml(response)  }
        f.yaml { Baggage::Response.yaml(response) }
      end
    end

    def return_error(response, code=400)
      respond_to do |f|
        f.html { halt code, Baggage::Response.json(response) }
        f.txt  { halt code, Baggage::Response.text(response) }
        f.json { halt code, Baggage::Response.json(response) }
        f.xml  { halt code, Baggage::Response.xml(response)  }
        f.yaml { halt code, Baggage::Response.yaml(response) }
      end
    end

    get '/subscribe' do 
      return_error({ :message => 'error', :error => 'email is missing' })
    end
    %w[ update rotate unsubscribe stats ].each do |call|
      get "/#{call}" do 
        return_error({ :message => 'error', :error => 'id is missing' })
      end
    end

    # GET /subscribe/user@domain
    # GET /subscribe/user@domain?expires=1
    get '/subscribe/:email' do
      param :email,     String, format: /^[a-zA-Z0-9\.\_\+\@\(\)]+$/, required: true
      param :expires,   Integer, min: Baggage::MIN_EXPIRES, max: Baggage::MAX_EXPIRES, default: Baggage::DEFAULT_EXPIRES
      param :name,      String, format: /^[a-zA-Z0-9\ \-\_\.]{,#{Baggage::NAME_LENGTH}}$/, default: "baggage.io"

      begin
        s = Subscriber.new
        s.subscribe(:email => params[:email], 
                    :expires => params[:expires],
                    :name => params[:name],
                    :last_admin_ip => request.ip)

        return_response({ :message => 'subscription sent' })
      rescue Exception => e
        return_error({ :message => 'error', :error => e.message })
      end
    end

    # GET /update/xxx?token=yyy
    get '/update/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true
      param :expires,   Integer, min: Baggage::MIN_EXPIRES, max: Baggage::MAX_EXPIRES, default: nil
      param :name,      String, format: /^[a-zA-Z0-9\ \-\_\.]{,#{Baggage::NAME_LENGTH}}$/, default: nil

      begin
        s = Subscriber.new
        s.update(:id => params[:id], 
                 :token => params[:token], 
                 :name => params[:name],
                 :expires => params[:expires],
                 :last_admin_ip => request.ip)

        return_response({ :message => 'updated' })
      rescue Exception => e
        return_error({ :message => 'error', :error => e.message })
      end

    end

    # GET /stats/xxx?token=yyy
    get '/stats/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true

      begin
        s = Subscriber.new
        stats = s.stats(:id => params[:id], 
                 :token => params[:token], 
                 :last_admin_ip => request.ip)

       return_response({ :message => 'stats', :stats => stats })
      rescue Exception => e
        return_error({ :message => 'error', :error => e.message })
      end
    end

    # GET /rotate/xxx?token=yyy
    # GET /rotate/xxx?token=yyy&expires=1
    get '/rotate/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true

      begin
        s = Subscriber.new
        s.rotate(:id => params[:id], 
                 :token => params[:token], 
                 :last_admin_ip => request.ip)

        return_response({ :message => 'rotated' })
      rescue Exception => e
        return_error({ :message => 'error', :error => e.message })
      end
    end

    # GET /unsubscribe/xxx?token=yyy
    get '/unsubscribe/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true

      begin
        s = Subscriber.new
        s.unsubscribe(:id => params[:id], 
                      :token => params[:token],
                      :last_admin_ip => request.ip)

        return_response({ :message => 'unsubscribed' })
      rescue Exception => e
        return_error({ :message => 'error', :error => e.message })
      end
    end

    # GET /send/xxx?token=yyy&subject=abc&message=def
    get '/send/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true
      param :subject,   String, required: true
      param :body,      String, required: true
      param :from,      String, default: MAIL_FROM_NAME

      begin
        s = Subscriber.new
        s.send(:id => params[:id],
               :token => params[:token],
               :subject => params[:subject],
               :body => params[:body],
               :from => params[:from],
               :last_sender_ip => request.ip)

        return_response({ :message => 'sent' })
      rescue Exception => e
        return_error({ :message => 'error', :error => e.message })
      end
    end

    post '/send/:id' do
      param :id,        String, format: /^[a-f0-9]{#{Baggage::ID_LENGTH}}$/, transform: :downcase, required: true
      param :token,     String, format: /^[a-f0-9]{#{Baggage::TOKEN_LENGTH}}$/, transform: :downcase, required: true
      param :subject,   String, required: true
      param :from,      String, default: MAIL_FROM_NAME

      request.body.rewind
      body = request.body.read

      begin
        s = Subscriber.new
        s.send(:id => params[:id],
               :token => params[:token],
               :subject => params[:subject],
               :body => body,
               :from => params[:from],
               :last_sender_ip => request.ip)

        return_response({ :message => 'sent' })
      rescue Exception => e
       return_error({ :message => 'error', :error => e.message })
      end
    end

    # GET /ping
    get '/ping' do
      return_response({ :message => 'pong' })
    end

    not_found do
     return_error({ :message => 'error', :error => 'not found' }, 404)
    end

  end
end

Baggage::App.run! if __FILE__ == $0

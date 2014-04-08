require 'sidekiq'
require 'mail'

Sidekiq.configure_client do |config|
  #config.redis = { :namespace => 'BaggageMailer', :size => 1 }
  config.redis = { :size => 1 }
end

class BaggageMailer
  include Sidekiq::Worker

  def perform(args = {})
    message = <<MESSAGE_END
From: #{args['from']}
To: #{args['to']}
Subject: #{args['subject']}

#{args['body']}
MESSAGE_END

    mail = Mail.new do
      to args['to']
      from args['from']
      subject args['subject']

      header['X-Sender'] = args['ip']
      header['X-X-Sender'] = args['ip']
      header['List-Unsubscribe'] = args['unsubscribe']
      header['X-Complaints-To'] = 'abuse@baggage.io'
      header['X-Mailer'] = 'api.baggage.io'
      text_part do 
        body args['body']
      end
    end

    if ENV.has_key?('SIDEKIQ_ENV') and ENV['SIDEKIQ_ENV'].downcase == 'development'
      File.open('mails.txt', 'a') { |f| f.write(mail.to_s) }
    else
      mail.deliver!
    end
  end
end

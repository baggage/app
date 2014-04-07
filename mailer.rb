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

    #File.open('mails', 'a') { |f| f.write(message) }
    mail = Mail.deliver do
      to args['to']
      from args['from']
      subject args['subject']

      header['X-Sender'] = args['ip']
      header['X-X-Sender'] = args['ip']
      header['List-Unsubscribe'] = args['unsubscribe']
      text_part do 
        body args['body']
      end
    end
  end
end

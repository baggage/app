require 'sidekiq'

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

    File.open('mails', 'a') { |f| f.write(message) }
    #Net::SMTP.start('localhost') do |smtp|
    #  smtp.send_message message
    #end
  end
end

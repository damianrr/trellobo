require 'action_mailer'

def to_boolean(str)
  str == "true"
end

ActionMailer::Base.raise_delivery_errors = true
ActionMailer::Base.delivery_method = :smtp
ENV['TRELLO_MAIL_ENABLE_STARTTLS_AUTO']
ActionMailer::Base.smtp_settings = {
  :address   => ENV['TRELLO_MAIL_ADDRESS'],
  :port      => ENV['TRELLO_MAIL_PORT'].to_i,
  :authentication => ENV['TRELLO_MAIL_AUTHENTICATION'].to_sym,
  :user_name      => ENV['TRELLO_MAIL_USERNAME'],
  :password       => ENV['TRELLO_MAIL_PASSWORD'],
  :enable_starttls_auto => to_boolean(ENV['TRELLO_MAIL_ENABLE_STARTTLS_AUTO'])
}
ActionMailer::Base.view_paths= File.dirname(__FILE__)

class CardMailer < ActionMailer::Base
  def send_card(to, card)
    @name = card.name
    mail(:to => to.to_s, :from => "trellobot@speedyrails.com", :subject => "Trellobot Card: \"#{@name}\"") do |format|
      format.html
    end
  end
end

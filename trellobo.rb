require 'cinch'
require 'trello'
require 'json'
require 'resolv'
require_relative './mailer.rb'

# You will need an access token to use ruby-trello 0.3.0 or higher, which trellobo depends on. To
# get it, you'll need to go to this URL:
#
# https://trello.com/1/connect?key=DEVELOPER_PUBLIC_KEY&name=trellobo&response_type=token&scope=read,write&expiration=never
#
# Substitute the DEVELOPER_PUBLIC_KEY with the value you'll supply in TRELLO_API_KEY below. At the end of this process,
# You'll be told to give some key to the app, this is what you want to put in the TRELLO_API_ACCESS_TOKEN_KEY below.
#
# there are 5 environment variables that must be set for the trellobot to behave
# the way he is supposed to -
#
# TRELLO_API_KEY : your Trello API developer key
# TRELLO_API_SECRET : your Trello API developer secret
# TRELLO_API_ACCESS_TOKEN_KEY : your Trello API access token key. See above how to generate it.
# TRELLO_BOARD_ID : the trellobot looks at only one board and the lists on it, put its id here
# TRELLO_BOT_QUIT_CODE : passcode to cause trellobot to quit - defaults to none
# TRELLO_BOT_CHANNEL : the name of the channel you want trellobot to live on
# TRELLO_BOT_CHANNEL_KEY : the password of the channel you want trellobot to live on. Optional
# TRELLO_BOT_NAME : the name for the bot, defaults to 'trellobot'
# TRELLO_BOT_SERVER : the server to connect to, defaults to 'irc.freenode.net'
# TRELLO_SSL : if ssl is required set this variable to "true" if not, do not set it at all. Optional
# TRELLO_SSL_PORT : if ssl is used set this variable to the port number that should be used. Optional
# TRELLO_ADD_CARDS_LIST : all cards are added at creation time to a default list. Set this variable to the
# TRELLO_MAIL_ADDRESS : address of the mail server used to send the cards
# TRELLO_MAIL_PORT : port of the mail server used to send the cards
# TRELLO_MAIL_AUTHENTICATION : type of authentication of the mail server used to send the cards
# TRELLO_MAIL_USERNAME : username in the mail server used to send the cards
# TRELLO_MAIL_PASSWORD : password for the username in the mail server used to send the cards
# TRELLO_MAIL_ENABLE_STARTTLS_AUTO : set tu true if the mail server uses tls, false otherwise


# name of that list. If not setted up, it will default to "To Do", and if a list with that name doesn't exist
# there will be features that will not work (Card's related ones). Optional



# DONE [moya]:
# Added support for ssl and custom ports
# Added support for channels with passwords
# Fixed bug on trello bot addressing
# DONE [dmn]:
# Improved support for ssl and custom ports
# Improved support for channels with passwords
# trello: card adding feature x
# trello: card <id> comment this is a comment on card <id>
# trello: card <id> move to Doing
# trello: card <id> add member joe
# trello: card <id> by user david (devuelve todas las cards a las que un usario esta asignado)
# trello: card <id> view joe@email.com (muestra todo el contenido de un card mediante el envio un correo formateado)

# TODO [dmn]:
# Crear un template html con la informacion importante del card
# Parametrizar la configuracion del envio de correos


$board = nil
$add_cards_list = nil

include Trello
include Trello::Authorization

Trello::Authorization.const_set :AuthPolicy, OAuthPolicy
OAuthPolicy.consumer_credential = OAuthCredential.new ENV['TRELLO_API_KEY'], ENV['TRELLO_API_SECRET']
OAuthPolicy.token = OAuthCredential.new ENV['TRELLO_API_ACCESS_TOKEN_KEY'], nil

def short_id(card)
  card.url.match(/\/(\d+)$/)[1]
end

def given_short_id_return_long_id(short_id)
  long_ids = $board.cards.collect { |c| c.id if c.url.match(/\/(\d+)$/)[1] == short_id.to_s}
  long_ids.delete_if {|e| e.nil?}
end

def get_list_by_name(name)
  $board.lists.find_all {|l| l.name.casecmp(name.to_s) == 0}
end

def validate_mail(email)
  unless email.blank?
    unless email =~ /^[a-zA-Z][\w\.-]*[a-zA-Z0-9]@[a-zA-Z0-9][\w\.-]*[a-zA-Z0-9]\.[a-zA-Z][a-zA-Z\.]*[a-zA-Z]$/
      raise "Your email address does not appear to be valid"
    else
      raise "Your email domain name appears to be incorrect" unless validate_email_domain(email)
    end
  end
end

def validate_email_domain(email)
  domain = email.match(/\@(.+)/)[1]
  Resolv::DNS.open do |dns|
    @mx = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
  end
  @mx.size > 0 ? true : false
end

def sync_board
  return $board.refresh! if $board
  $board = Trello::Board.find(ENV['TRELLO_BOARD_ID'])
  $add_cards_list = $board.lists.detect { |l| l.name.casecmp(ENV['TRELLO_ADD_CARDS_LIST']) == 0 }
end

def say_help(msg)
  msg.reply "I can tell you the open cards on the lists on your Trello board. Just address me with the name of the list (it's not case sensitive)."
  msg.reply "For example - trellobot: ideas"
  msg.reply "I also understand the these commands : "
  msg.reply "  -> 1. help - shows this!"
  msg.reply "  -> 2. sync - resyncs my cache with the board."
  msg.reply "  -> 3. lists - show me all the board list names"
end

bot = Cinch::Bot.new do
  configure do |c|
    # Initialize defaults for optional envs
    ENV['TRELLO_BOT_QUIT_CODE'] ||= ""
    ENV['TRELLO_BOT_NAME'] ||= "trellobot"
    ENV['TRELLO_BOT_SERVER'] ||= "irc.freenode.net"
    ENV['TRELLO_ADD_CARDS_LIST'] ||= "To Do"

    c.server = ENV['TRELLO_BOT_SERVER']
    c.nick = ENV['TRELLO_BOT_NAME']

    if !ENV["TRELLO_BOT_CHANNEL_KEY"].nil? and ENV["TRELLO_BOT_CHANNEL_KEY"] != ""
      c.channels = ["#{ENV['TRELLO_BOT_CHANNEL']} #{ENV['TRELLO_BOT_CHANNEL_KEY']}"]
    else
      c.channels = [ENV['TRELLO_BOT_CHANNEL']]
    end
    if ENV['TRELLO_SSL'] == "true"
      c.port = ENV['TRELLO_SSL_PORT']
      c.ssl.use = true
    end
    sync_board
  end

  # trellobot is polite, and will only reply when addressed
  on :message, /^#{ENV['TRELLO_BOT_NAME']}[_]*:/ do |m|
    # if trellobot can't get thru to the board, then send the human to the human url
    sync_board unless $board
    unless $board
      m.reply "I can't seem to get the list of ideas from Trello, sorry. Try here: https://trello.com/board/#{ENV['TRELLO_BOARD_ID']}"
      bot.halt
    end

    # trellobot: what up?  <- The bit we are interested in is past the ':'
    parts = m.message.split(':',2)
    searchfor = parts[1].strip.downcase

    case searchfor
      when /debug/
      debugger
      when /^card add/
      if $add_cards_list.nil?
        m.reply "Can't add card. It wasn't found any list named: #{ENV['TRELLO_ADD_CARDS_LIST']}."
      else
        m.reply "Creating card ... "
        name = searchfor.strip.match(/^card add (.+)$/)[1]
        card = Trello::Card.create(:name => name, :list_id => $add_cards_list.id)
        m.reply "Created card #{card.name} with id: #{short_id(card)}."
      end
      when /^card \d+ comment/
      m.reply "Commenting on card ... "
      card_regex = searchfor.match(/^card (\d+) comment (.+)/)
      card_id = given_short_id_return_long_id(card_regex[1])
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{card_regex[1]}"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do ... aborting"
      else
        comment = card_regex[2]
        card = Trello::Card.find(card_id[0].to_s)
        card.add_comment comment
        m.reply "Added \"#{comment}\" comment to \"#{card.name}\" card"
      end
      when /^card \d+ move to \w+/
      m.reply "Moving card ... "
      regex = searchfor.match(/^card (\d+) move to (\w+)/)
      list = get_list_by_name(regex[2].to_s)
      card_id = given_short_id_return_long_id(regex[1].to_s)
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{regex[1]}. Aborting"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do ... aborting"
      else
        if list.count == 0
          m.reply "Couldn't be found any list named: \"#{regex[2].to_s}\"."
        elsif list.count > 1
          m.reply "There are #{list.count} lists named: #{regex[2].to_s}. Don't know what to do ... aborting"
        else
          card = Trello::Card.find(card_id[0])
          list = list[0]
          if card.list.name.casecmp(list.name) == 0
            m.reply "Card \"#{card.name}\" is already on list \"#{list.name}\"."
          else
            card.move_to_list list
            m.reply "Moved card \"#{card.name}\" to list \"#{list.name}\"."
          end
        end
      end
      when /^card \d+ add member \w+/
      m.reply "Adding member to card ... "
      regex = searchfor.match(/^card (\d+) add member (\w+)/)
      card_id = given_short_id_return_long_id(regex[1].to_s)
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{regex[1]}"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do ... aborting"
      else
        card = Trello::Card.find(card_id[0])
        membs = card.members.collect {|m| m.username}
        begin
          member = Trello::Member.find(regex[2])
        rescue
          member = nil
        end
        if member.nil?
          m.reply "User \"#{regex[2]}\" doesn't exist in Trello."
        elsif membs.include? regex[2]
          m.reply "#{member.full_name} is already assigned to card \"#{card.name}\"."
        else
          card.add_member(member)
          m.reply "Added \"#{member.full_name}\" to card \"#{card.name}\"."
        end
      end
      when /^card by user \w+/
      username = searchfor.match(/^card by user (\w+)/)[1]
      cards = []
      $board.cards.each do |card|
        members = card.members.collect { |mem| mem.username }
        if members.include? username
          cards << card
        end
      end
      inx = 1
      if cards.count == 0
        m.reply "User \"#{username}\" has no cards assigned."
      end
      cards.each do |c|
        m.reply "  ->  #{inx.to_s}. #{c.name} (id: #{short_id(c)}) from list: #{c.list.name}"
        inx += 1
      end
      when /^card \d+ view (.+)/
      m.reply "Sending mail with card content ... "
      regex = searchfor.match(/^card (\d+) view (.+)/)
      card_id = given_short_id_return_long_id(regex[1].to_s)
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{regex[1]}"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do ... aborting"
      else
        card = Trello::Card.find(card_id[0])
        msg_err = nil
        begin
          validate_mail(regex[2])
        rescue => e
          msg_err = e.message
        end
        if msg_err.nil?
          begin
            email = CardMailer.send_card(regex[2], card)
            email.deliver
          rescue => e
            m.reply e.message
            m.reply "An error ocurred sending the mail. Sorry for the inconvenience."
            break
          end
          m.reply "Mailed the card \"#{card.name}\" to #{regex[2]}"
        else
          m.reply msg_err
        end
      end
      when /lists/
        $board.lists.each { |l|
          m.reply "  ->  #{l.name}"
        }
      when /help/
      when /\?/
        say_help(m)
      when /sync/
        sync_board
        m.reply "Ok, synced the board, #{m.user.nick}."
      else
      if searchfor.length > 0
        # trellobot presumes you know what you are doing and will attempt
        # to retrieve cards using the text you put in the message to him
        # at least the comparison is not case sensitive
        list = $board.lists.detect { |l| l.name.casecmp(searchfor) == 0 }
        if list.nil?
          m.reply "There's no list called <#{searchfor}> on the board, #{m.user.nick}. Sorry."
        else
          cards = list.cards
          if cards.count == 0
            m.reply "Nothing doing on that list today, #{m.user.nick}."
          else
            ess = (cards.count == 1) ? "" : "s"
            m.reply "I have #{cards.count} card#{ess} today"
            inx = 1
            cards.each do |c|
              membs = c.members.collect {|m| m.full_name }
              if membs.count == 0
                m.reply "  ->  #{inx.to_s}. #{c.name} (id: #{short_id(c)})"
              else
                m.reply "  ->  #{inx.to_s}. #{c.name} (id: #{short_id(c)}) (members: #{membs.to_s.gsub!("[","").gsub!("]","").gsub!("\"","")})"; inx += 1
              end
              inx += 1
            end
          end
        end
      else
        say_help(m)
      end
    end
  end

  # if trellobot loses his marbles, it's easy to disconnect him from the server
  # note that if you are doing a PaaS deploy, he may respawn depending on what
  # the particular hosting env is (e.g. Heroku will start him up again)
  on :private, /^quit(\s*)(\w*)/ do |m, blank, code|
    bot.quit if ENV['TRELLO_BOT_QUIT_CODE'].eql?(code)

    if code.empty?
      m.reply "There is a quit code required for this bot, sorry."
    else
      m.reply "That is not the correct quit code required for this bot, sorry."
    end
  end
end

bot.start

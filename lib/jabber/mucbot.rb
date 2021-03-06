#--
# "THE BEER-WARE LICENSE" (Revision 42):
# <vivien@didelot.org> wrote this file. As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return. Vivien Didelot
#++

require 'rubygems'
require 'xmpp4r'
require 'xmpp4r/muc'

module Jabber

  class MUCBot

    # Creates a new Jabber::MUCBot object with the specified +config+ Hash,
    # which must contain +nick+ and +server+ (or +jid+), +password+, and +room+ at a minimum.
    #
    # If you do not pass an explicit +jid+, the default of +nick+@+server+ will
    # be used.
    #
    # You may optionally give a +debug+ option. If it is omitted, it will be
    # set to false and no debug messages will be printed.
    #
    # You may optionally give a +keep_alive+ option. If it is omitted,
    # it will be set to true and Thread.stop will be called.
    # That is useful to set it to false if you have a main loop
    # in your bot algorithm or if you simply want to call others methods
    # like :send after join.
    #
    # The bot will be +public+.
    #
    # By default, a Jabber::MUCBot has no command.
    #
    #   # A configured MUC Bot.
    #   bot = Jabber::MUCBot.new(
    #     :nick       => 'bot',
    #     :password   => 'secret',
    #     :server     => 'example.com',
    #     :room       => 'myroom',
    #     :debug      => true, # optional
    #     :keep_alive => true # optional
    #   )
    #
    #   # Or with a jid:
    #   bot = Jabber::MUCBot.new(
    #     :jid      => 'bot@example.com',
    #     :password => 'secret',
    #     :room     => 'myroom'
    #   )
    #
    def initialize(config)
      @config = config
      # Sets keep_alive true by default or use the one from the config hash.
      @config[:keep_alive] = true unless @config.key? :keep_alive
      # Parses :nick and :server if a :jid key is given,
      # else build :jid from :nick and :server.
      if @config.key? :jid
        @config[:nick] = @config[:jid].split('@').first
        @config[:server] = @config[:jid].split('@').last
      else
        @config[:jid] = "#{@config[:nick]}@#{@config[:server]}"
      end

      Jabber.debug = @config[:debug] || false

      @commands = []

      # Connect the bot to the server.
      jid = Jabber::JID.new(@config[:jid])
      @jabber = Jabber::Client.new(jid)
      @jabber.connect
      @jabber.auth(@config[:password])

      @room = Jabber::MUC::MUCClient.new(@jabber)
    end

    # Add a command to the bot's repertoire.
    #
    # Commands consist of a regular expression and a callback block.
    # The regular expression (+regex+) is used to detect the presence of
    # the command in an incoming message.
    #
    # The command parameters will be parsed from text between () in the regex.
    # e.g. giving /^cmd\s(.+)$/ will gives the parameter. If there was more than
    # one occurrence, an array would be given.
    #
    # The specified callback block will be triggered when the bot receives a
    # message that matches the given command regex. The callback block
    # will have access to the sender and the parameters (not including
    # the command itsef), and should either return a String response
    # or +nil+. If a callback block returns a String response, the response will
    # be sent to the room.
    #
    # Examples:
    #
    #   # Say 'puts foo' and 'foo' will be written to $stdout.
    #   # The bot will also respond with "'foo' written to $stdout."
    #   add_command(/^puts\s+(.+)$/) do |sender, message|
    #     puts "#{sender} says #{message}."
    #     "'#{message}' written to $stdout."
    #   end
    #
    #   # 'puts!' is a non-responding version of 'puts'.
    #   add_command(/^puts!\s+(.+)$/) do |sender, message|
    #     puts "#{sender} says #{message}."
    #     nil
    #   end
    #
    #  # 'rand' is a command that produces a random number from 0 to 10
    #  add_command(/^rand$/) { rand(10).to_s }
    #
    #  # 'rand2 <min> <max>' is a command that produces a random number from <min> to <max>
    #  add_command(/^rand2\s+(\d+)\s+(\d+)$/) { |sender, params|
    #    min = params.first.to_i
    #    max = params.last.to_i
    #
    #    rand(max - min) + min
    #  }
    #
    def add_command(regex, &callback)
      # Add the command spec - used for parsing incoming commands.
      @commands << {
        :regex     => regex,
        :callback  => callback
      }
    end

    # Join the bot to the room and enable callbacks.
    def join
      nick = @config[:nick]
      serv = @config[:server]
      room = @config[:room]

      jid = Jabber::JID.new("#{room}@conference.#{serv}/#{nick}")
      @room.join(jid)

      @room.add_message_callback do |message|
        #TODO do not process messages before bot connection
        if message_valid? message
          Jabber.debuglog("from: " + message.from.resource +
                          " to: " + message.to.resource +
                          " body: " + message.body)
          parse_thread = Thread.new do
            parse_command(message.from.resource, message.body)
          end

          parse_thread.join
        end
      end

      # Keep alive the current thread
      # NOTE Thread.stop is needed if the bot has no main loop.
      # If it has, this line is not needed.
      # Another problem with this line is that commands like
      # bot.send() won't work after this line.
      # Only pre-added commands will work.
      Thread.stop if @config[:keep_alive]
    end

    # Send a message to the room.
    def send(message)
      if message.is_a? Jabber::Message
        @room.send(message)
      else
        m = Jabber::Message.new
        m.body = message
        @room.send(m)
      end
    end

    # Disconnect the bot. Once the bot has been disconnected, there is no way
    # to restart it by issuing a command.
    def disconnect
      if @jabber.connected?
        send "Goodbye!"
        @jabber.disconnect
      end
    end

    # Customize a welcome message for new connected people.
    # The given callback takes a |user| parameter and
    # should return the welcome message.
    #
    #   welcome { |guy| "Hello #{guy}!" }
    def welcome(&callback)
      @room.add_join_callback do |message|
        response = callback.call(message.from.resource)
        send(response) unless response.nil?
      end
    end

    private

    def message_valid?(message) #:nodoc:
      message.type == :groupchat &&
        !message.from.resource.nil? &&
        message.from.resource != @config[:nick] &&
        !message.body.nil? && !message.first_element('delay')
    end

    # Parses the given command message for the presence of a known command by
    # testing it against each known command's regex. If a known command is
    # found, the command parameters are passed on to the callback block like this:
    # nil if there is no parameter, the parameter string if there is just one occurrence,
    # or an array if there is more than one occurence.
    # parsed from text occurrences between () in the given regex.
    # If a String result is present it is sent to the sender.
    def parse_command(sender, message) #:nodoc:
      @commands.each do |command|
        match = message.strip.match(command[:regex])
        unless match.nil?
          # Gives nil, a string or an array depending on captures size.
          params = (match.captures.size <= 1) ? match.captures.first : match.captures

          response = command[:callback].call(sender, params)
          send(response) unless response.nil?

          return
        end
      end
    end
  end
end

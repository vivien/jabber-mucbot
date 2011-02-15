#--
# Copyright (c) 2009 Brett Stimmerman <brettstimmerman@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#   * Neither the name of this project nor the names of its contributors may be
#     used to endorse or promote products derived from this software without
#     specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#++

require 'rubygems'
require 'xmpp4r'
require 'xmpp4r/muc'

module Jabber

  class MUCBot

    # Creates a new Jabber::MUCBot object with the specified +config+ Hash,
    # which must contain +nick+, +password+, +server+, and +room+ at a minimum.
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
    #   # A confiugured MUC Bot.
    #   bot = Jabber::MUCBot.new(
    #     :nick       => 'bot',
    #     :password   => 'secret',
    #     :server     => 'example.com',
    #     :room       => 'myroom',
    #     :debug      => true, # optional
    #     :keep_alive => true # optional
    #   )
    #
    def initialize(config)
      @config = config
      @config[:keep_alive] = true unless @config.key? :keep_alive
      Jabber.debug = @config[:debug] || false
      @commands = []

      connect

      @room = Jabber::MUC::MUCClient.new(@jabber)
    end

    # Add a command to the bot's repertoire.
    #
    # Commands consist of a regular expression and a callback block.
    # The regular expression (+regex+) is used to detect the presence of
    # the command in an incoming message.
    #
    # The specified callback block will be triggered when the bot receives a
    # message that matches the given command regex. The callback block
    # will have access to the sender and the message text (not including
    # the command itsef), and should either return a String response
    # or +nil+. If a callback block returns a String response, the response will
    # be sent to the room.
    #
    # Examples:
    #
    #   # Say 'puts foo' and 'foo' will be written to $stdout.
    #   # The bot will also respond with "'foo' written to $stdout."
    #   add_command(/^puts\s+.+$/) do |sender, message|
    #     puts "#{sender} says #{message}."
    #     "'#{message}' written to $stdout."
    #   end
    #
    #   # 'puts!' is a non-responding version of 'puts'.
    #   add_command(/^puts!\s+.+$/) do |sender, message|
    #     puts "#{sender} says #{message}."
    #     nil
    #   end
    #
    #  # 'rand' is a command that produces a random number from 0 to 10
    #  add_command(/^rand$/) { rand(10).to_s }
    #
    def add_command(regex, &callback)
      # Add the command spec - used for parsing incoming commands.
      @commands << {
        :regex     => regex,
        :callback  => callback
      }
    end

    # :on is an alias for :add_command.
    # So the rand command could be given with:
    # on(/^rand$/) { rand(10).to_s }
    alias :on :add_command

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

    # This class method is a short hand to fastly set up a bot.
    # It will create the bot, connect and join it to the room.
    # a block can be given to customize the bot before initialization.
    #
    #   Jabber::MUCBot.start config do |bot|
    #     bot.welcome { |guy| "Hello #{guy}!" }
    #     bot.on(/^me$/) do |sender, message|
    #       bot.send("You are #{sender}!")
    #     end
    #   end
    def self.start(config)
      bot = MUCBot.new(config)
      yield bot if block_given?
      bot.join
    end

    private

    # Connect the bot to the server.
    def connect #:nodoc:
      nick = @config[:nick]
      serv = @config[:server]
      pass = @config[:password]
      jid  = @config[:jid] || "#{nick}@#{serv}"

      jid = Jabber::JID.new(jid)
      @jabber = Jabber::Client.new(jid)
      @jabber.connect
      @jabber.auth(pass)

      @jabber.on_exception do |excp, stream, where|
        @jabber.connect
        @jabber.auth(pass)

        join
      end
    end

    def message_valid?(message) #:nodoc:
      message.type == :groupchat &&
        !message.from.resource.nil? &&
        message.from.resource != @config[:nick] &&
        !message.body.nil? && !message.first_element('delay')
    end

    # Parses the given command message for the presence of a known command by
    # testing it against each known command's regex. If a known command is
    # found, the command parameters are passed on to the callback block, minus
    # the command trigger. If a String result is present it is sent to the
    # sender.
    def parse_command(sender, message) #:nodoc:
      @commands.each do |command|
        unless (message.strip =~ command[:regex]).nil?
          params = message
          #if message.include? ' '
            #params = message.sub(/^\S+\s+(.*)$/, '\1')
          #end

          response = command[:callback].call(sender, params)
          send(response) unless response.nil?

          return
        end
      end
    end
  end
end

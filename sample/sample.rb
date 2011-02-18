#!/usr/bin/env ruby

#--
# "THE BEER-WARE LICENSE" (Revision 42):
# <vivien@didelot.org> wrote this file. As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return. Vivien Didelot
#++

require 'rubygems'
require 'jabber/mucbot'

# Configure a public bot
config = {
  :nick     => 'bot',
  :password => 'secret',
  :server   => 'example.com',
  :room     => 'myroom'
}

# Create a new bot
bot = Jabber::MUCBot.new(config)

# Give the bot a private command, 'puts', with a response message
bot.add_command(/^puts\s+.+$/) do |sender, message|
  puts "#{sender} says #{message}."
  "'#{message}' written to $stdout."
end

# Give the bot another private command, 'puts!', without a response message
bot.add_command(/^puts!\s+.+$/) do |sender, message|
  puts "#{sender} says #{message}."
  nil
end

# Give the bot a public command, 'rand'
bot.add_command(/^rand$/) { rand(10).to_s }

# Add a customized welcome message
bot.welcome { |guy| "Hello #{guy}!" }

# Unleash the bot
bot.join

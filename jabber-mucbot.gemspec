Gem::Specification.new do |s|
  s.name     = 'jabber-mucbot'
  s.version  = '0.0.1'
  s.author   = 'Vivien Didelot'
  s.email    = 'vivien.didelot@gmail.com'
  s.homepage = 'https://github.com/v0n/jabber-mucbot'
  s.platform = Gem::Platform::RUBY
  s.summary  = 'Easily create simple regex powered Jabber Multi Users Chat bots.'
  s.description = 'Jabber::MUCBot makes it simple to create and command your own ' +
                  'Jabber MUC bot. Bots are created by defining commands powered ' +
                  'by regular expressions and Ruby.'

  s.rubyforge_project = 'jabber-mucbot'

  s.files = [
    'LICENSE',
    'README.rdoc',
    'lib/jabber/mucbot.rb'
  ]

  s.require_path = 'lib'

  s.required_ruby_version = '>=1.8.4'

  s.add_dependency('xmpp4r')
end

require "shrb/version"
require 'coolline'
require 'rouge'
require 'shrb/configuration'
require 'shrb/lexer'


module Shrb
  class Abort < Exception; end

  class << self

    def start
      # 実行可能なコマンド
      external_commands = []
      ENV['PATH'].split(':').each do |path|
        Dir.children(File.expand_path(path)).each do |child|
          external_commands << child if File.executable?(File.join(path, child))
        end
      end

      coolline = Coolline.new do |c|
        c.transform_proc = proc do
          theme = Rouge::Themes::Colorful.new
          formatter = Rouge::Formatters::Terminal256.new(theme)
          lexer = Rouge::Lexers::Shell.new
          formatter.format(lexer.lex(c.line))
        end
        c.completion_proc = proc do
          word = c.completed_word
          external_commands.grep(/\A#{Regexp.quote word}/) # タブ補完の候補
        end
        c.bind "\C-d" do |cool|
          exit
        end
      end

      while true
        begin
          result = coolline.readline(Configuration.prompt)

          lexer = Lexer.new(result)
          lexer.parse

          lexer.assign
          lexer.execute

        rescue Interrupt
          puts ""
          next
        rescue Commands::CommandNotFound => e
          puts e.message
        rescue => e
          puts "error: #{e.message}"
          puts e.backtrace
          exit
        end
      end
    end
  end
end

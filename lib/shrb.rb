require "shrb/version"
require 'coolline'
require 'rouge'
require 'shrb/configuration'
require 'shrb/lexer'
require 'shrb/scanner'


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

      scanner = Scanner.new

      while true
        begin
          prompt = Configuration.prompt
          unless scanner.empty?
            prompt = scanner.current_program.to_prompt + prompt
          end
          result = coolline.readline(prompt)

          #lexer = Lexer.new(result)
          #lexer.parse

          #lexer.assign
          #lexer.execute

          scanner.scan(result)

          if scanner.executable?
            scanner.execute
            scanner = Scanner.new
          end

        rescue Interrupt
          puts ""
          next
        rescue => e
          puts "error: #{e.message}"
          puts e.backtrace
          exit
        end
      end
    end
  end
end

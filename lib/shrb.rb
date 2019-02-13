require "shrb/version"
require 'shrb/configuration'
require 'shrb/readline'
require 'shrb/scanner'

module Shrb
  class Abort < Exception; end

  class << self
    def start
      readline = Readline.factory
      scanner = Scanner.new

      while true
        begin
          prompt = Configuration.prompt
          unless scanner.empty?
            prompt = scanner.current_program.to_prompt + prompt
          end
          result = readline.readline(prompt)

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

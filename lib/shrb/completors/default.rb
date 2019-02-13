module Shrb
  class Completors
    class Default
      class << self
        def completion
          proc do |readline|
            _completion(readline.completed_word)
          end
        end

        private

        def external_commands
          @external_commands ||= []
          return @external_commands unless @external_commands.count.zero?

          # 実行可能なコマンド
          ENV['PATH'].split(':').each do |path|
            Dir.children(File.expand_path(path)).each do |child|
              @external_commands << child if File.executable?(File.join(path, child))
            end
          end

          @external_commands
        end

        def _completion(word)
          if word == ''
            []
          else
            external_commands.sort.grep(/\A#{Regexp.quote word}/) # タブ補完の候補
          end
        end
      end
    end
  end
end


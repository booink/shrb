module Shrb
  class Transformers
    class Default
      class << self
        def transform
          proc do |line|
            _transform(line)
          end
        end

        private

        def _transform(line)
          theme = Rouge::Themes::Colorful.new
          formatter = Rouge::Formatters::Terminal256.new(theme)
          lexer = Rouge::Lexers::Shell.new
          formatter.format(lexer.lex(line))
        end
      end
    end
  end
end


module Shrb
  class Configuration
    class << self
      def prompt
        @prompt || '-> '
      end

      def prompt=(text)
        @prompt = text
      end

      def completor
        return @completor if @completor
        require 'shrb/completors/default'
        Completors::Default
      end

      def completor=(completor)
        @completor = completor
      end

      def transformer
        return @transformer if @transformer
        require 'shrb/transformers/default'
        Transformers::Default
      end

      def transformer=(transformer)
        @transformer = transformer
      end
    end
  end
end

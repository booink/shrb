module Shrb
  class Configuration
    class << self
      def prompt
        @prompt || '-> '
      end

      def prompt=(text)
        @prompt = text
      end
    end
  end
end

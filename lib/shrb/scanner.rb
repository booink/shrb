module Shrb
  class Scanner
    def initialize
      @program = Program.new
    end

    def scan(text)
      #@program.scan
      @text = text
      @program.scan(@text.chars)
    end

    def execute
      @program.execute
    end

    def executable?
      @program.executable?
    end

    class Base
      attr_accessor :token, :continue_to_succeed, :continue_to_fail

      def initialize
        @commands = Commands.new
        @end = false
        @continue_to_succeed = false
        @continue_to_fail = false
        @token = []
      end

      def end?
        @end
      end

      def scan(chars)
        @chars = chars
        loop do
          break unless _scan(@chars.shift)
        end
      end

      def execute
        @commands.execute
      end

      def executable?
        return false if @commands.empty?
        @commands.last.executable?
      end

      private

      def _scan(char)
        case char
        when '{'
          group = Group.new
          group.scan(@chars)
          @commands.push(group)
        when '('
          subshell = SubShell.new
          subshell.scan(@chars)
          @commands.push(subshell)
        when '|'
          if @chars.first == '|'
            @chars.shift
            @commands.last.continue_to_fail = true
          else
            pipe = Pipe.new(@commands.pop)
            pipe.scan(@chars)
            @commands.push(pipe)
          end
        when '&'
          if @chars.first == '&'
            @chars.shift
            @commands.last.continue_to_succeed = true
          else
            daemon = Daemon.new(@commands.pop)
            daemon.scan(@chars)
            @commands.push(daemon)
          end
        when nil
          return
        else
          @chars.unshift(char)
          command = Command.new
          command.scan(@chars)
          @commands.push(command)
        end
      end
    end

    class Program < Base
      def _scan(char)
        unless @commands.empty? || executable?
          @chars.unshift(char)
          return @commands.last.scan(@chars)
        end
        super
      end
    end

    class SubShell < Base
      def _scan(char)
        case char
        when ')'
          @end = true
          return
        when nil
          return
        else
          super
        end
      end
    end

    class Group < Base
      def _scan(char)
        unless @commands.empty? || executable?
          @chars.unshift(char)
          return @commands.last.scan(@chars)
        end

        case char
        when '}'
          @end = true
          return
        when nil
          return
        else
          super
        end
      end
    end

    class Command < Base
      def _scan(char)
        unless @commands.empty? || executable?
          @chars.unshift(char)
          return @commands.last.scan(@chars)
        end

        case char
        when ';', '}', ')', nil
          @end = true
          return
        when '{', '('
          @end = true
          @chars.unshift(char)
          return
        when '|'
          @end = true
          @chars.unshift(char)
          return
        when "'"
          single_quoted_text = SingleQuotedText.new
          single_quoted_text.token << char
          single_quoted_text.scan(@chars)
          @commands.push(single_quoted_text)
        when '"'
          double_quoted_text = DoubleQuotedText.new
          double_quoted_text.token << char
          double_quoted_text.scan(@chars)
          @commands.push(double_quoted_text)
        else
          literal_text = LiteralText.new
          @chars.unshift(char)
          literal_text.scan(@chars)
          @commands.push(literal_text)
        end
      end

      def execute
        token = @commands.map(&:token).join("")
        return if token == ' '
        pid = Process.fork do
          yield if block_given?
          Process.exec token
        end
        _, status = Process.waitpid2(pid)
        if @continue_to_succeed
          return status.success?
        end
        if @continue_to_fail
          return !status.success?
        end
        return true
      end
    end

    class Daemon < Base
      def initialize(previous_command)
        @previous_command = previous_command
        super(chars)
      end

      def execute
        return unless @previous_command

        @previous_command.execute do
          Process.daemon
        end
      end
    end

    class Pipe < Base
      def initialize(previous_command)
        @previous_command = previous_command
        super()
      end

      def execute
        next_command = @commands.pop
        return unless @previous_command && next_command

        r, w = IO.pipe
        @previous_command.execute do
          $stdout.reopen w
        end
        w.close

        next_command.execute do
          $stdin.reopen r
        end
        r.close

        $stdin = STDIN
        $stdout = STDOUT
      end
    end

    class LiteralText < Base
      def executable?
        end?
      end

      private

      def _scan(char)
        case char
        when nil
          @end = true
          return
        when ';', '}', ')', '|'
          @chars.unshift(char)
          @end = true
          return
        when ' '
          @end = true
          @token << char
          return
        else
          @token << char
        end
      end
    end

    class SingleQuotedText < Base
      def executable?
        end?
      end

      private

      def _scan(char)
        if char.nil?
          return
        elsif char == "'" && @token.last != '\\'
          @token << char
          @end = true
          return
        else
          @token << char
        end
      end
    end

    class DoubleQuotedText < Base
      def executable?
        end?
      end

      private

      def _scan(char)
        if char.nil?
          return
        elsif char == '"' && @token.last != '\\'
          @token << char
          @end = true
          return
        else
          @token << char
        end
      end
    end

    class Commands < Array
      def execute
        each do |command|
          unless command.nil?
            break unless command.execute
          end
        end
      end
    end
  end
end

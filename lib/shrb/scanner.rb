module Shrb
  class Scanner
    def initialize(text)
      @text = text
      @program = Program.new(@text.chars)
    end

    def scan
      @program.scan
    end

    def execute
      @program.execute
    end

    class Program
      attr_accessor :continue_to_succeed, :continue_to_fail
      def initialize(chars)
        @chars = chars
        @commands = Commands.new
        @continue_to_succeed = false
        @continue_to_fail = false
        scan
      end

      def scan
        loop do
          char = @chars.shift
          case char
          when '{'
            group = Group.new(@chars)
            @commands.push(group)
          when '|'
            if @chars.first == '|'
              @chars.shift
              @commands.last.continue_to_fail = true
            else
              pipe = Pipe.new(@chars, @commands.pop)
              @commands.push(pipe)
            end
          when '&'
            if @chars.first == '&'
              @chars.shift
              @commands.last.continue_to_succeed = true
            else
              daemon = Daemon.new(@chars, @commands.pop)
              @commands.push(daemon)
            end
          when nil
            return
          else
            @chars.unshift(char)
            command = Command.new(@chars)
            @commands.push(command)
          end
        end
      end

      def execute
        @commands.execute
      end
    end

    class Command < Program
      def initialize(chars)
        @token = []
        super
      end

      def scan
        loop do
          char = @chars.shift
          case char
          when ';', '}', nil
            return
          when '|'
            @chars.unshift(char)
            return
          when "'"
            single_quoted_text = SingleQuotedText.new(@chars)
            @token += ["'", single_quoted_text.token, "'"].flatten
          when '"'
            double_quoted_text = DoubleQuotedText.new(@chars)
            @token += ['"', double_quoted_text.token, '"'].flatten
          else
            @token << char
          end
        end
      end

      def execute
        pid = Process.fork do
          yield if block_given?
          Process.exec @token.join('')
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

    class Group < Program
      def scan
        loop do
          case @chars.shift
          when '}', nil
            return
          when '{'
            group = Group.new(@chars)
            @commands.push(group)
          else
            command = Command.new(@chars)
            @commands.push(command)
          end
        end
      end
    end

    class Daemon < Program
      def initialize(chars, previous_command)
        @previous_command = previous_command
        super(chars)
      end

      def execute
        return unless @previous_command

        r, w = IO.pipe
        @previous_command.execute do
          Process.daemon
        end
        w.close
      end
    end

    class Pipe < Program
      def initialize(chars, previous_command)
        @previous_command = previous_command
        super(chars)
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

    class SingleQuotedText < Program
      def initialize(chars)
        @token = []
        super
      end

      def token
        @token
      end

      def scan
        loop do
          char = @chars.shift
          if char == "'" && @token.last != '\\'
            return
          else
            @token << char
          end
        end
      end
    end

    class DoubleQuotedText < Program
      def initialize(chars)
        @token = []
        super
      end

      def token
        @token
      end

      def scan
        loop do
          char = @chars.shift
          if char == '"' && @token.last != '\\'
            return
          else
            @token << char
          end
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

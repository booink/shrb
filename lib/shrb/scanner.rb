require 'open3'

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
      @program.prepare
      @program.execute
      @program.cleanup
    end

    def executable?
      @program.executable?
    end

    def empty?
      @program.commands.empty?
    end

    def current_program
      @program.current_program
    end

    class Base
      attr_accessor :commands, :token, :continue_to_succeed, :continue_to_fail

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

      def prepare
        @commands.prepare
      end

      def execute
        @commands.execute
      end

      def cleanup
        @commands.cleanup
      end

      def executable?
        return false if @commands.empty?
        @commands.last.executable?
      end

      def to_prompt
        ""
      end

      def current_program
        last_command = @commands.last
        if last_command.executable?
          self
        else
          last_command.current_program
        end
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
            @commands.push(daemon)
          end
        when '='
          environment_variable = EnvironmentVariable.new(@commands.pop)
          environment_variable.scan(@chars)
          @commands.push(environment_variable)
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
      def to_prompt
        "("
      end

      def executable?
        end?
      end

      private

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
      def to_prompt
        "{"
      end

      def executable?
        end?
      end

      private

      def _scan(char)
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
        when ';', nil
          @end = true
          return
        when '}', ')', '{', '(', '|', '&'
          @chars.unshift(char)
          @end = true
          return
        when '='
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
        when '`'
          back_quoted_text = BackQuotedText.new
          back_quoted_text.token << char
          back_quoted_text.scan(@chars)
          @commands.push(back_quoted_text)
        else
          literal_text = LiteralText.new
          @chars.unshift(char)
          literal_text.scan(@chars)
          @commands.push(literal_text)
        end
      end

      def execute(reader_pipe: nil, writer_pipe: nil, wait: true)
        token = @commands.map(&:execute).join('')
        return if token == ' '

        tokens = token.split(' ')
        pid = Process.fork do
          yield if block_given?
          STDIN.reopen(reader_pipe) if reader_pipe
          STDOUT.reopen(writer_pipe) if writer_pipe
          Process.exec(tokens.shift, *tokens)
        end
        reader_pipe.close if reader_pipe
        writer_pipe.close if writer_pipe
        _, status = Process.waitpid2(pid) if wait
        if @continue_to_succeed
          return status.success?
        end
        if @continue_to_fail
          return !status.success?
        end
        return true
      end
    end

    class EnvironmentVariable < Command
      def initialize(previous_command)
        @variable_name = previous_command.commands.first.execute
        @backup = ENV[@variable_name]
        super()
      end

      def execute
        raise 'must specified variable name' unless @variable_name

        ENV[@variable_name] = @commands.first.execute
      end

      def cleanup
        ENV[@variable_name] = @backup
      end
    end

    class Daemon < Base
      def initialize(previous_command)
        super()
        @commands.push(previous_command)
      end

      def execute
        return if @commands.empty?

        @commands.last.execute do
          Process.daemon
        end
      rescue => e
        puts "e: #{e.inspect}"
      end
    end

    class Pipe < Base
      def initialize(previous_command)
        @previous_command = previous_command
        super()
      end

      def execute(reader_pipe: nil, wait: true)
        next_command = @commands.pop
        return unless @previous_command && next_command

        r, w = IO.pipe
        @previous_command.execute(reader_pipe: reader_pipe, writer_pipe: w, wait: false)
        next_command.execute(reader_pipe: r, wait: false)

        Process.waitall if wait
      end
    end

    class LiteralText < Base
      def executable?
        end?
      end

      def prepare; end
      def cleanup; end

      def execute
        @token.join('')
      end

      private

      def _scan(char)
        case char
        when nil
          @end = true
          return
        when ';', '}', ')', '|', '"', "'", '`', '='
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
      def to_prompt
        "'"
      end

      def executable?
        end?
      end

      def current_program
        self
      end

      def prepare; end
      def cleanup; end

      def execute
        @token.shift
        @token.pop
        @token.join('')
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
      def to_prompt
        '"'
      end

      def executable?
        end?
      end

      def current_program
        self
      end

      def prepare; end
      def cleanup; end

      def execute
        @token.shift
        @token.pop
        @token.join('')
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

    class BackQuotedText < Base
      def to_prompt
        '`'
      end

      def executable?
        end?
      end

      def current_program
        self
      end

      def prepare; end
      def cleanup; end

      def execute
        @token.shift
        @token.pop
        stdout, _  = Open3.capture2(@token.join(''))
        stdout
      end

      private

      def _scan(char)
        if char.nil?
          return
        elsif char == '`' && @token.last != '\\'
          @token << char
          @end = true
          return
        else
          @token << char
        end
      end
    end

    class Commands < Array
      def prepare
        each do |command|
          unless command.nil?
            break unless command.prepare
          end
        end
      end

      def execute
        each do |command|
          unless command.nil?
            break unless command.execute
          end
        end
      end

      def cleanup
        each do |command|
          unless command.nil?
            break unless command.cleanup
          end
        end
      end
    end
  end
end

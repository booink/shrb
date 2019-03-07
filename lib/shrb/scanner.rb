require 'open3'

module Shrb
  class Scanner
    def initialize
      @program = Program.new
    end

    def scan(text)
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
      attr_accessor :commands, :token, :continue_to_succeed, :continue_to_fail, :in, :out, :error

      def initialize
        @commands = Commands.new
        @end = false
        @continue_to_succeed = false
        @continue_to_fail = false
        @token = []
        @in = STDIN
        @out = STDOUT
        @error = STDERR
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
            if @chars.first == '&'
              @chars.shift
              pipe.with_stderr = true
            end
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
      attr_accessor :redirects

      def initialize
        @redirects = []
        super
      end

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
          if literal_text.redirect?
            redirect = Redirect.new
            redirect.scan(@chars)
            @redirects.push(redirect)
          else
            @commands.push(literal_text)
          end
        end
      end

      def execute(force_redirects: [], wait: true)
        token = @commands.map(&:execute).join('')
        return if token == ' '

        @redirects += force_redirects

        tokens = token.split(' ')
        pid = Process.fork do
          yield if block_given?

          @redirects.each do |redirect|
            redirect.source.reopen(redirect.destination)
          end
          Process.exec(tokens.shift, *tokens)
        end
        @redirects.each do |redirect|
          redirect.destination.close
        end
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

    class Redirect
      attr_accessor :source, :destination

      def initialize(source = nil, destination = nil)
        @source = source
        @destination = destination
      end

      def scan(chars)
        @chars = chars
        _chars = _scan
        _chars.join('').scan(/\A(\d*)([<>][<>|&]?)(.*)\z/) do |source, operator, destination|
          source = nil if source == ''
          destination = nil if destination == ''
          case operator
          when '>', '>|'
            output(source, destination)
          when '>>'
            appending_output(source, destination)
          when '>&'
            duplicating_output(source, destination)
          when '<'
            input(source, destination)
          when '<<'
            here_document(source, destination)
          when '<&'
            duplicating_input(source, destination)
          when '<>'
            open_for_reading_and_writing(source, destination)
          end
        end
        @end = true
      end

      private

      # [fd]>output or [fd]>|output
      def output(source, destination)
        @source = source.nil? ? STDOUT : IO.open(source.to_i)
        destination = _scan.join('') unless destination
        raise ArgumentError, 'argument is missing' if destination == ''
        @destination = open(destination, 'w')
      end

      # [fd]>>output
      def appending_output(source, destination)
        @source = source.nil? ? STDOUT : IO.open(source.to_i)
        destination = _scan.join('') unless destination
        raise ArgumentError, 'argument is missing' if destination == ''
        @destination = open(destination, 'a')
      end

      # [fd]>&output
      def duplicating_output(source, destination)
        @source = source.nil? ? STDERR : IO.open(source.to_i)
        @destination = destination.nil? ? STDOUT : IO.open(destination.to_i)
      end

      # [fd]<output
      def input(source, destination)
        @source = source.nil? ? STDIN : IO.open(source.to_i)
        destination = _scan.join('') unless destination
        raise ArgumentError, 'argument is missing' if destination == ''
        @destination = open(destination, 'r')
      end

      def here_document(source, destination)
      end

      # [fd]<&output
      def duplicating_input(source, destination)
        @source = source.nil? ? STDERR : IO.open(source.to_i)
        @destination = destination.nil? ? STDIN : IO.open(destination.to_i)
      end

      def open_for_reading_and_writing(source, destination)
      end

      def _scan
        _chars = []
        loop do
          char = @chars.shift
          break if char.nil? || char == ' '

          _chars.push(char)
        end
        _chars
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
      attr_accessor :with_stderr

      def initialize(previous_command)
        @previous_command = previous_command
        @with_stderr = false
        super()
      end

      def execute(readable_io: nil, wait: true)
        next_command = @commands.pop
        return unless @previous_command && next_command

        r, w = IO.pipe
        redirects = []
        redirects << Redirect.new(STDIN, readable_io) if readable_io
        redirects << Redirect.new(STDOUT, w)
        redirects << Redirect.new(STDERR, w) if with_stderr
        @previous_command.execute(force_redirects: redirects, wait: false)
        next_command.execute(force_redirects: [Redirect.new(STDIN, r)], wait: false)

        Process.waitall if wait
      end
    end

    class LiteralText < Base
      def initialize
        super
        @redirect = false
      end

      def redirect?
        @redirect
      end

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
        when '<', '>'
          @redirect = true
          @chars.unshift(@token, char)
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
        @token.shift # remove backquote
        @token.pop # remove backquote
        program = Program.new
        program.scan(@token)
        program.execute
        #stdout, _  = Open3.capture2(@token.join(''))
        #stdout
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

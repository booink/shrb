module Shrb
  class Lexer
    def initialize(text)
      @text = text
      @tokens = []
      @commands = Commands.new
    end

    LOGICAL_OPERATOR_PATTERN = '(\|\||&&)'
    COMMAND_END_PATTERN = '([\|;&])'
    WORD_PATTERN = %q{([^\s\\\'\"\|\;]+)}
    SINGLE_QUOTE_PATTERN = %q{('[^\']*')}
    DOUBLE_QUOTE_PATTERN = %q{("(?:[^\"\\\]|\\.)*")}
    ESCAPE_PATTERN = %q{(\\\.?)}
    GARBAGE_PATTERN = '(\S)'
    SEPARATER_PATTERN = '(\s+|\z)?'

    def parse
      field = ''
      pattern = /\G(?>#{LOGICAL_OPERATOR_PATTERN}|#{COMMAND_END_PATTERN}|#{WORD_PATTERN}|#{SINGLE_QUOTE_PATTERN}|#{DOUBLE_QUOTE_PATTERN}|#{ESCAPE_PATTERN}|#{GARBAGE_PATTERN})#{SEPARATER_PATTERN}/m
      @text.scan(pattern) do |logical, command_end, word, sq, dq, esc, garbage, sep|
        #puts "end: '#{command_end}', word: '#{word}', sq: '#{sq}', dq: \"#{dq}\", esc: '#{esc}', garbage: '#{garbage}', sep: '#{sep}'"
        raise ArgumentError, "Unmatched double quote: #{@text.inspect}" if garbage
        field << (word || sq || (dq || esc).gsub(/\\(.)/, '\\1')) unless command_end || logical
        if sep || command_end || logical
          if field != ""
            @tokens << field
            field = ''
          end
          @tokens << logical if logical
          @tokens << command_end if command_end
          if sep && sep != ""
            @tokens << sep
          end
        end
      end
      #puts "tokens: #{@tokens}"
      self
    end

    def assign
      last_command = nil
      in_group = false
      loop do
        token = @tokens.shift
        if command_end?(token)
          @commands << last_command
          last_command = nil
        end

        break if token.nil?

        case token
        when /^[0-9A-Za-z_]+=/
          @commands.push(EnvironmentVariable.new(token))
        when '&&'
          @commands.last.continue_to_succeed = true
        when '||'
          @commands.last.continue_to_fail = true
        when '&'
          @commands.last.daemonize
        when '|'
          pipe = Pipe.new
          pipe.out = @commands.pop
          pipe.in = assign_next
          @commands.push(pipe)
        when '{'
          in_group = true
        when '}'
          in_group = false
          @commands.push(last_command)
        when ';'
          # no op
        else
          last_command ||= in_group ? CommandGroup.new : Command.new
          last_command.tokens.push(token)
        end
      end

      puts @commands.inspect
    end

    def assign_next
      command = Command.new

      loop do
        token = @tokens.shift
        return command if command_end?(token)

        command.tokens.push(token)
      end
    end

    def execute
      parse if @tokens.count.zero?
      assign if @commands.count.zero?
      @commands.execute
    end

    private

    def command_end?(token)
      return false unless in_group && token == '}'
      return true if [nil, ';', '|', '{', '(', ')', '&', '&&', '||'].include?(token)
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

    class Base
      attr_accessor :tokens
      attr_accessor :stdin, :stdout, :stderr
      attr_accessor :continue_to_succeed, :continue_to_fail

      def initialize(token = nil)
        @tokens = []
        @tokens.push(token) unless token.nil?
        @string = nil
        @daemon = false
        @continue_to_succeed = false
        @continue_to_fail = false
      end

      def stringify
        @string ||= valid_tokens.join("")
        @string
      end
      alias to_s stringify

      def valid_tokens
        tokens = @tokens.dup
        tokens.shift if tokens.first =~ /\s+/
        tokens.pop if tokens.last =~ /\s+/
        tokens
      end

      def command
        valid_tokens.first
      end

      def command_options
        tokens = valid_tokens.dup
        tokens.shift
        tokens.select { |token| token !~ /\s+/ }
      end

      def execute
        pid = Process.fork do
          yield if block_given?
          Process.exec command, *command_options
        end
        Process.daemon if @daemonize
        _, status = Process.waitpid2(pid)
        if @continue_to_succeed
          return status.success?
        end
        if @continue_to_fail
          return !status.success?
        end
        return true
      end

      def daemonize
        @daemon = true
      end
    end

    class Command < Base; end

    class Pipe < Base
      attr_accessor :in, :out

      def execute
        return unless @in && @out

        r, w = IO.pipe
        @out.execute do
          $stdout.reopen w
        end
        w.close

        @in.execute do
          $stdin.reopen r
        end
        r.close

        $stdin = STDIN
        $stdout = STDOUT
      end
    end

    class SubShell < Base
    end

    class CommandGroup < Base
      def execute
        devide.each(&:execute)
      end

      private

      def devide
        Lexer.new(stringify).parse.assign.commands
      end
    end

    class BraceExpansion < Base
    end

    class EnvironmentVariable < Base
      def execute
        splited = stringify.split(/=/, 2)
        name = splited[0]
        value = splited[1]
        ENV[name] = enquote(value)
        puts "ENV[#{name}]: #{value}"
      end

      private

      def enquote(value)
        text = ""
        value.scan(/'([^\']*)'|"((?:[^\"\\]|\\.)*)"|`([^`]*)`|.*/m) do |sq, dq, bq, other|
          puts "sq: #{sq}; dq: #{dq}; bq: #{bq}; other: #{other}"
          if bq
            text = Lexer.new(bq).execute
          else
            text = sq || dq || other
          end
        end
        text
      end
    end
  end
end

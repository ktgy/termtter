# -*- coding: utf-8 -*-
require 'singleton'

config.plugins.command_line.
  set_default(:shortcut_setting,
              { ':' => '',
                'd' => 'direct',
                'D' => 'delete',
                'f' => 'fib',
                'F' => 'favorite',
                'l' => 'list',
                'o' => 'open',
                'p' => 'profile',
                'R' => 'reply',
                's' => 'search',
                't' => 'retweet',
                'u' => 'update',
                'c' => lambda do
                  system('clear')
                end,
                'L' => lambda do
                  puts '-' *
                    `stty size`.chomp.
                    sub(/^\d+\s(\d+)$/, '\\1').to_i
                end,
                'q' => lambda do
                  Termtter::Client.call_commands('quit')
                end,
                'r' => lambda do
                  Termtter::Client.call_commands('replies')
                end,
                '?' => lambda do
                  Termtter::Client.call_commands('help')
                end,
                "\e" => lambda do
                  system('screen', '-X', 'eval', 'copy')
                end
              })

module Termtter
  class CommandLine
    include Singleton

    STTY_ORIGIN = `stty -g`.chomp

    class << self

      def start
        instance.start
      end

      def stop
        instance.stop
      end
    end

    def start
      start_input_thread
    end

    def stop
      @input_thread.kill if @input_thread
    end

    def call(command_text)
      # Example:
      # t.register_hook(:post_all, :point => :prepare_command) do |s|
      #   "update #{s}"
      # end
      Client.get_hooks('prepare_command').each {|hook|
        command_text = hook.call(command_text)
      }
      Client.call_commands(command_text)
    end

    def prompt
      prompt_text = config.prompt
      Client.get_hooks('prepare_prompt').each {|hook|
        prompt_text = hook.call(prompt_text)
      }
      prompt_text
    end

    private

    def start_input_thread
      setup_readline()
      trap_setting()
      @input_thread = Thread.new do
        loop do
          begin
            value = config.plugins.command_line.shortcut_setting[wait_keypress]
            Client.pause
            case value
            when String
              call_prompt(value)
            when Proc
              value.call
            end
          ensure
            Client.resume
          end
        end
      end
      @input_thread.join
    end

    def call_prompt(command)
      Client.call_commands("curry #{command}")
      if buf = Readline.readline(ERB.new(prompt).result(Termtter::API.twitter.__send__(:binding)), true)
        Readline::HISTORY.pop if buf.empty?
        begin
          call(buf)
        rescue Exception => e
          Client.handle_error(e)
        end
      else
        puts
      end
    ensure
      Client.call_commands('uncurry')
    end

    def wait_keypress
      system('stty', '-echo', '-icanon')
      c = STDIN.getc
      return [c].pack('c')
    ensure
      system('stty', STTY_ORIGIN)
    end

    def setup_readline
      if Readline.respond_to?(:basic_word_break_characters=)
        Readline.basic_word_break_characters= "\t\n\"\\'`><=;|&{("
      end
      Readline.completion_case_fold = true
      Readline.completion_proc = lambda {|input|
        begin
          words = Client.commands.map {|name, command| command.complement(input) }.flatten.compact

          if words.empty?
            Client.get_hooks(:completion).each do |hook|
              words << hook.call(input) rescue nil
            end
          end

          words.flatten.compact
        rescue Exception => e
          Client.handle_error(e)
        end
      }
      vi_or_emacs = config.editing_mode
      unless vi_or_emacs.empty?
        Readline.__send__("#{vi_or_emacs}_editing_mode")
      end
    end

    def trap_setting()
      begin
        trap("INT") do
          begin
            system "stty", STTY_ORIGIN
          ensure
            Client.call_commands('exit')
          end
        end
      rescue ArgumentError
      rescue Errno::ENOENT
      end
    end
  end

  Client.register_hook(:initialize_command_line, :point => :launched) do
    CommandLine.start
  end

  Client.register_hook(:finalize_command_line, :point => :exit) do
    CommandLine.stop
  end

  Client.register_command(:vi_editing_mode) do |arg|
    Readline.vi_editing_mode
  end

  Client.register_command(:emacs_editing_mode) do |arg|
    Readline.emacs_editing_mode
  end
end

# -*- coding: utf-8 -*-

require 'uri'
require 'tweetstream'
require File.dirname(__FILE__) + '/../termtter/active_rubytter'

config.plugins.stream.set_default :max_following, 400

module Termtter::Client

  class << self
    if defined?(DB)
      def friends(max = 999999)
        Status.group(:user_id).
          select(:user_id, :screen_name).
          join(:users, :id => :user_id).
          order(:COUNT.sql_function.desc).take(max)
      end
    else
      def friends(max = 1/0.0)
        friends = []
        page    = 0
        begin
          friends += tmp = Termtter::API::twitter.friends(config.user_name, :page => page+=1)
          p friends.length
        rescue
        end until (tmp.empty? or friends.length > max)
        friends.take(max)
      end
    end

    def kill_thread(name)
      config.plugins.stream.__send__(name).kill rescue nil
      config.plugins.stream.__assign__(name, nil)
    end
    private :kill_thread
  end

  help = ['keyword_stream KEYWORDS', 'Tracking keyword using Stream API']
  register_command(:keyword_stream, :help => help) do |arg|
    next if arg.empty?
    args = arg.split
    case args[0]
    when ':stop'
      kill_thread :keyword_stream
      puts 'stream is down'
    else
      next if config.plugins.stream.keyword_stream.class == Thread
      puts "streaming: #{args.join(', ')}"
      config.plugins.stream.keyword_stream = Thread.new do
        TweetStream::Client.new(config.user_name, config.password).
          filter(:track => args) do |status|
          output [Termtter::ActiveRubytter.new(status)], :update_friends_timeline
          Readline.refresh_line
        end
      end
    end

    at_exit do
      kill_thread :keyword_stream
    end
  end

  help = ['hash_stream HASHTAG', 'Tracking hashtag using Stream API']
  register_command(:hash_stream, :help => help) do |arg|
    arg = "##{arg}" unless /^#/ =~ arg
    call_commands("keyword_stream #{arg}")
  end

  help = ['stream USERNAME', 'Tracking users using Stream API']
  register_command(:stream, :help => help) do |arg|
    catch(:exit) do
      args = arg.split

      case args[0]
      when ':stop'
        kill_thread :thread
        puts 'stream is down'
        throw :exit
      end

      throw :exit if config.plugins.stream.thread.class == Thread

      targets = args.map { |name|
        Termtter::API.twitter.user(name).id rescue nil
      }

      max = config.plugins.stream.max_following
      unless targets and targets.length > 0
        keys = [:user_id, :"`user_id`", :id, :"`id`"]
        targets = friends(max).map{ |u|
          keys.map{ |k| u[k] rescue nil}.compact.first
        }.compact
      end

      config.plugins.stream.thread = Thread.new do
        begin
          current_targets = targets.take(max)
          targets = targets.take(max)
          puts "streaming #{current_targets.length} friends."
          TweetStream::Client.new(config.user_name, config.password).
            filter(:follow => current_targets) do |status|
            output [Termtter::ActiveRubytter.new(status)], :update_friends_timeline
            Readline.refresh_line
          end
        rescue(NoMethodError) => e    # #<NoMethodError: private method `split' called for nil:NilClass>
          puts "stream seems broken (#{e.inspect})."
          max -= 10 if max > 10
          retry
        end
      end

      at_exit do
        kill_thread :stream
      end
    end
  end
end


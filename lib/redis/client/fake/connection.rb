# frozen_string_literal: true

module Redis
  module Client
    module Fake
      # Fake Redis connection that stores data in-memory
      class Connection
        attr_reader :config

        def initialize(config, connect_timeout: nil, read_timeout: nil, write_timeout: nil)
          @config = config
          @connect_timeout = connect_timeout
          @read_timeout = read_timeout
          @write_timeout = write_timeout
          @connected = true
          @pending_reads = 0
          @storage = self.class.shared_storage
          @command_queue = []
        end

        def self.shared_storage
          @shared_storage ||= Storage.new
        end

        def self.reset_shared_storage!
          @shared_storage = Storage.new
        end

        def connected?
          @connected
        end

        def close
          @connected = false
          @pending_reads = 0
          nil
        end

        def reconnect
          close
          @connected = true
          true
        end

        def revalidate
          if @pending_reads > 0
            close
            false
          else
            connected?
          end
        end

        attr_writer :read_timeout, :write_timeout

        def write(command)
          raise ConnectionError, "Connection closed" unless @connected

          @command_queue << command
        end

        def write_multi(commands)
          raise ConnectionError, "Connection closed" unless @connected

          @command_queue.concat(commands)
        end

        def read(_timeout = nil)
          raise ConnectionError, "Connection closed" unless @connected
          raise ConnectionError, "No command to read response for" if @command_queue.empty?

          command = @command_queue.shift
          execute_command(command)
        end

        def call(command, timeout)
          @pending_reads += 1
          write(command)
          result = read(connection_timeout(timeout))
          @pending_reads -= 1

          if result.is_a?(Exception)
            result._set_command(command) if result.respond_to?(:_set_command)
            result._set_config(config) if result.respond_to?(:_set_config)
            raise result
          else
            result
          end
        end

        def call_pipelined(commands, timeouts, exception: true)
          first_exception = nil
          size = commands.size
          results = Array.new(size)
          @pending_reads += size
          write_multi(commands)

          size.times do |index|
            timeout = timeouts && timeouts[index]
            result = read(connection_timeout(timeout))
            @pending_reads -= 1

            if result.is_a?(Exception)
              result._set_command(commands[index]) if result.respond_to?(:_set_command)
              result._set_config(config) if result.respond_to?(:_set_config)
              first_exception ||= result
            end

            results[index] = result
          end

          raise first_exception if first_exception && exception

          results
        end

        def measure_round_trip_delay
          start_time = Time.now
          call(["PING"], @read_timeout)
          ((Time.now - start_time) * 1000).round(2)
        end

        private

        def execute_command(command)
          return nil if command.nil? || command.empty?

          cmd_name = command.first.to_s.upcase
          args = command[1..-1] || []

          case cmd_name
          # Connection commands
          when "PING"
            @storage.ping(args.first)
          when "HELLO"
            # Redis 6+ HELLO command - return basic server info
            [
              "server", "redis",
              "version", "7.0.0-fake",
              "proto", 3,
              "id", 1,
              "mode", "standalone",
              "role", "master"
            ]

          # String commands
          when "SET"
            key = args[0]
            value = args[1]
            options = parse_set_options(args[2..-1])
            @storage.set(key, value, options)
          when "GET"
            @storage.get(args.first)
          when "INCR"
            @storage.incr(args.first)
          when "INCRBY"
            key = args[0]
            increment = args[1].to_i
            @storage.incrby(key, increment)
          when "MGET"
            @storage.mget(*args)
          when "MSET"
            @storage.mset(*args)

          # Key commands
          when "EXISTS"
            args.count { |key| @storage.exists?(key) }
          when "DEL"
            @storage.del(*args)
          when "UNLINK"
            @storage.unlink(*args)
          when "EXPIRE"
            key = args[0]
            seconds = args[1].to_i
            @storage.expire(key, seconds)
          when "EXPIREAT"
            key = args[0]
            timestamp = args[1].to_i
            @storage.expireat(key, timestamp)
          when "TTL"
            @storage.ttl(args.first)
          when "PTTL"
            @storage.pttl(args.first)
          when "TYPE"
            @storage.type(args.first)
          when "KEYS"
            pattern = args.first || "*"
            @storage.keys(pattern)

          # Database commands
          when "FLUSHALL"
            @storage.flushall
          when "FLUSHDB"
            @storage.flushdb
          when "DBSIZE"
            @storage.dbsize

          # Hash commands
          when "HGET"
            key = args[0]
            field = args[1]
            @storage.hget(key, field)
          when "HSET"
            key = args[0]
            field = args[1]
            value = args[2]
            @storage.hset(key, field, value)
          when "HSETNX"
            key = args[0]
            field = args[1]
            value = args[2]
            @storage.hsetnx(key, field, value)
          when "HGETALL"
            @storage.hgetall(args.first)
          when "HDEL"
            key = args.shift
            @storage.hdel(key, *args)
          when "HINCRBY"
            key = args[0]
            field = args[1]
            increment = args[2].to_i
            @storage.hincrby(key, field, increment)
          when "HLEN"
            @storage.hlen(args.first)
          when "HMGET"
            key = args.shift
            @storage.hmget(key, *args)

          # List commands
          when "LPUSH"
            key = args.shift
            @storage.lpush(key, *args)
          when "RPUSH"
            key = args.shift
            @storage.rpush(key, *args)
          when "LPOP"
            key = args[0]
            count = args[1] ? args[1].to_i : nil
            @storage.lpop(key, count)
          when "RPOP"
            key = args[0]
            count = args[1] ? args[1].to_i : nil
            @storage.rpop(key, count)
          when "LLEN"
            @storage.llen(args.first)
          when "LINDEX"
            key = args[0]
            index = args[1].to_i
            @storage.lindex(key, index)
          when "LRANGE"
            key = args[0]
            start = args[1].to_i
            stop = args[2].to_i
            @storage.lrange(key, start, stop)
          when "LREM"
            key = args[0]
            count = args[1].to_i
            element = args[2]
            @storage.lrem(key, count, element)
          when "LMOVE"
            source = args[0]
            destination = args[1]
            wherefrom = args[2]
            whereto = args[3]
            @storage.lmove(source, destination, wherefrom, whereto)

          # Set commands
          when "SADD"
            key = args.shift
            @storage.sadd(key, *args)
          when "SREM"
            key = args.shift
            @storage.srem(key, *args)
          when "SCARD"
            @storage.scard(args.first)
          when "SISMEMBER"
            key = args[0]
            member = args[1]
            @storage.sismember(key, member)
          when "SMEMBERS"
            @storage.smembers(args.first)

          # Sorted set commands
          when "ZADD"
            key = args.shift
            @storage.zadd(key, *args)
          when "ZCARD"
            @storage.zcard(args.first)
          when "ZINCRBY"
            key = args[0]
            increment = args[1].to_f
            member = args[2]
            @storage.zincrby(key, increment, member)
          when "ZRANGE"
            key = args[0]
            start = args[1].to_i
            stop = args[2].to_i
            withscores = args[3]&.upcase == "WITHSCORES"
            @storage.zrange(key, start, stop, withscores: withscores)
          when "ZREM"
            key = args.shift
            @storage.zrem(key, *args)
          when "ZREMRANGEBYRANK"
            key = args[0]
            start = args[1].to_i
            stop = args[2].to_i
            @storage.zremrangebyrank(key, start, stop)
          when "ZREMRANGEBYSCORE"
            key = args[0]
            min = args[1].to_f
            max = args[2].to_f
            @storage.zremrangebyscore(key, min, max)

          # Pub/Sub commands
          when "PUBLISH"
            channel = args[0]
            message = args[1]
            @storage.publish(channel, message)

          # Script commands
          when "SCRIPT"
            subcommand = args[0]&.upcase
            case subcommand
            when "LOAD"
              @storage.script_load(args[1])
            when "EXISTS"
              @storage.script_exists(*args[1..-1])
            else
              error_class = defined?(RedisClient::CommandError) ? RedisClient::CommandError : StandardError
              error_class.new("ERR unknown SCRIPT subcommand '#{subcommand}'")
            end

          # Bitfield commands
          when "BITFIELD"
            key = args.shift
            @storage.bitfield(key, *args)
          when "BITFIELD_RO"
            key = args.shift
            @storage.bitfield_ro(key, *args)

          else
            # Return a generic error for unsupported commands
            error_class = defined?(RedisClient::CommandError) ? RedisClient::CommandError : StandardError
            error_class.new("ERR unknown command '#{cmd_name}'")
          end
        rescue StandardError => e
          # Convert any unexpected errors to Redis command errors
          error_class = defined?(RedisClient::CommandError) ? RedisClient::CommandError : StandardError
          error_class.new("ERR #{e.message}")
        end

        def parse_set_options(args)
          options = {}
          i = 0
          while i < args.length
            case args[i].to_s.upcase
            when "EX"
              options[:ex] = args[i + 1].to_i
              i += 2
            when "PX"
              options[:px] = args[i + 1].to_i
              i += 2
            when "EXAT"
              options[:exat] = args[i + 1].to_i
              i += 2
            when "PXAT"
              options[:pxat] = args[i + 1].to_i
              i += 2
            else
              i += 1
            end
          end
          options
        end

        def connection_timeout(timeout)
          return timeout unless timeout && timeout > 0

          timeout + begin
            config.read_timeout
          rescue StandardError
            5.0
          end
        end
      end
    end
  end
end

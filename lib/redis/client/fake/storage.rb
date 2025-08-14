# frozen_string_literal: true

module Redis
  module Client
    module Fake
      # Thread-safe in-memory storage for Redis data
      class Storage
        def initialize
          @data = {}
          @expires = {}
          @mutex = Mutex.new
        end

        def get(key)
          @mutex.synchronize do
            return nil if expired?(key)

            @data[key]
          end
        end

        def set(key, value, options = {})
          @mutex.synchronize do
            @data[key] = value
            set_expiration(key, options[:ex], options[:px], options[:exat], options[:pxat])
            "OK"
          end
        end

        def exists?(key)
          @mutex.synchronize do
            return false if expired?(key)

            @data.key?(key)
          end
        end

        def del(*keys)
          @mutex.synchronize do
            count = 0
            keys.each do |key|
              next unless @data.key?(key)

              @data.delete(key)
              @expires.delete(key)
              count += 1
            end
            count
          end
        end

        def keys(pattern = "*")
          @mutex.synchronize do
            all_keys = @data.keys.reject { |key| expired?(key) }
            if pattern == "*"
              all_keys
            else
              # Simple glob pattern matching
              regex_pattern = pattern.gsub("*", ".*").gsub("?", ".")
              regex = Regexp.new("\\A#{regex_pattern}\\z")
              all_keys.select { |key| key.match?(regex) }
            end
          end
        end

        def flushall
          @mutex.synchronize do
            @data.clear
            @expires.clear
            "OK"
          end
        end

        def flushdb
          flushall
        end

        def dbsize
          @mutex.synchronize do
            @data.count { |key, _| !expired?(key) }
          end
        end

        def expire(key, seconds)
          @mutex.synchronize do
            return 0 unless @data.key?(key)

            @expires[key] = Time.now + seconds
            1
          end
        end

        def expireat(key, timestamp)
          @mutex.synchronize do
            return 0 unless @data.key?(key)

            @expires[key] = Time.at(timestamp)
            1
          end
        end

        def ttl(key)
          @mutex.synchronize do
            return -2 unless @data.key?(key) # key doesn't exist
            return -1 unless @expires.key?(key) # key exists but no expiration

            ttl_seconds = @expires[key] - Time.now
            return -2 if ttl_seconds <= 0 # expired

            ttl_seconds.to_i
          end
        end

        def ping(message = nil)
          message || "PONG"
        end

        private

        def expired?(key)
          return false unless @expires.key?(key)

          if Time.now >= @expires[key]
            @data.delete(key)
            @expires.delete(key)
            true
          else
            false
          end
        end

        def set_expiration(key, ex, px, exat, pxat)
          if ex
            @expires[key] = Time.now + ex
          elsif px
            @expires[key] = Time.now + (px / 1000.0)
          elsif exat
            @expires[key] = Time.at(exat)
          elsif pxat
            @expires[key] = Time.at(pxat / 1000.0)
          end
        end
      end
    end
  end
end

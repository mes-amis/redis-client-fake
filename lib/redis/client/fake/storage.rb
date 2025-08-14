# frozen_string_literal: true

require "set"

module Redis
  module Client
    module Fake
      # Thread-safe in-memory storage for Redis data
      class Storage
        def initialize
          @data = {}
          @expires = {}
          @pubsub_channels = {}
          @scripts = {}
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

        # String operations
        def incr(key)
          @mutex.synchronize do
            current = (@data[key] || "0").to_i
            @data[key] = (current + 1).to_s
            current + 1
          end
        end

        def incrby(key, increment)
          @mutex.synchronize do
            current = (@data[key] || "0").to_i
            @data[key] = (current + increment).to_s
            current + increment
          end
        end

        def mget(*keys)
          @mutex.synchronize do
            keys.map { |key| expired?(key) ? nil : @data[key] }
          end
        end

        def mset(*key_value_pairs)
          @mutex.synchronize do
            key_value_pairs.each_slice(2) do |key, value|
              @data[key] = value
            end
            "OK"
          end
        end

        def type(key)
          @mutex.synchronize do
            return "none" unless @data.key?(key) && !expired?(key)

            value = @data[key]
            case value
            when String then "string"
            when Array then "list"
            when Hash then "hash"
            when Set then "set"
            else "string"
            end
          end
        end

        def unlink(*keys)
          del(*keys) # Same as DEL for in-memory storage
        end

        def pttl(key)
          @mutex.synchronize do
            return -2 unless @data.key?(key) # key doesn't exist
            return -1 unless @expires.key?(key) # key exists but no expiration

            ttl_ms = (@expires[key] - Time.now) * 1000
            return -2 if ttl_ms <= 0 # expired

            ttl_ms.to_i
          end
        end

        # Hash operations
        def hget(key, field)
          @mutex.synchronize do
            return nil if expired?(key)

            hash = @data[key]
            return nil unless hash.is_a?(Hash)

            hash[field]
          end
        end

        def hset(key, field, value)
          @mutex.synchronize do
            @data[key] = {} unless @data[key].is_a?(Hash)
            existing = @data[key].key?(field)
            @data[key][field] = value
            existing ? 0 : 1
          end
        end

        def hsetnx(key, field, value)
          @mutex.synchronize do
            @data[key] = {} unless @data[key].is_a?(Hash)
            return 0 if @data[key].key?(field)

            @data[key][field] = value
            1
          end
        end

        def hgetall(key)
          @mutex.synchronize do
            return [] if expired?(key)

            hash = @data[key]
            return [] unless hash.is_a?(Hash)

            hash.to_a.flatten
          end
        end

        def hdel(key, *fields)
          @mutex.synchronize do
            return 0 if expired?(key)

            hash = @data[key]
            return 0 unless hash.is_a?(Hash)

            count = 0
            fields.each do |field|
              count += 1 if hash.delete(field)
            end
            count
          end
        end

        def hincrby(key, field, increment)
          @mutex.synchronize do
            @data[key] = {} unless @data[key].is_a?(Hash)
            current = (@data[key][field] || "0").to_i
            @data[key][field] = (current + increment).to_s
            current + increment
          end
        end

        def hlen(key)
          @mutex.synchronize do
            return 0 if expired?(key)

            hash = @data[key]
            return 0 unless hash.is_a?(Hash)

            hash.size
          end
        end

        def hmget(key, *fields)
          @mutex.synchronize do
            return Array.new(fields.size) if expired?(key)

            hash = @data[key]
            return Array.new(fields.size) unless hash.is_a?(Hash)

            fields.map { |field| hash[field] }
          end
        end

        # List operations
        def lpush(key, *values)
          @mutex.synchronize do
            @data[key] = [] unless @data[key].is_a?(Array)
            values.each { |value| @data[key].unshift(value) }
            @data[key].size
          end
        end

        def rpush(key, *values)
          @mutex.synchronize do
            @data[key] = [] unless @data[key].is_a?(Array)
            values.each { |value| @data[key].push(value) }
            @data[key].size
          end
        end

        def lpop(key, count = nil)
          @mutex.synchronize do
            return nil if expired?(key)

            list = @data[key]
            return nil unless list.is_a?(Array)

            if count
              result = list.shift(count)
              result.empty? ? nil : result
            else
              list.shift
            end
          end
        end

        def rpop(key, count = nil)
          @mutex.synchronize do
            return nil if expired?(key)

            list = @data[key]
            return nil unless list.is_a?(Array)

            if count
              result = list.pop(count).reverse
              result.empty? ? nil : result
            else
              list.pop
            end
          end
        end

        def llen(key)
          @mutex.synchronize do
            return 0 if expired?(key)

            list = @data[key]
            return 0 unless list.is_a?(Array)

            list.size
          end
        end

        def lindex(key, index)
          @mutex.synchronize do
            return nil if expired?(key)

            list = @data[key]
            return nil unless list.is_a?(Array)

            list[index]
          end
        end

        def lrange(key, start, stop)
          @mutex.synchronize do
            return [] if expired?(key)

            list = @data[key]
            return [] unless list.is_a?(Array)

            # Handle negative indices
            start = list.size + start if start < 0
            stop = list.size + stop if stop < 0

            return [] if start > list.size - 1 || start < 0

            stop = list.size - 1 if stop >= list.size
            return [] if stop < start

            list[start..stop] || []
          end
        end

        def lrem(key, count, element)
          @mutex.synchronize do
            return 0 if expired?(key)

            list = @data[key]
            return 0 unless list.is_a?(Array)

            removed = 0
            if count > 0
              # Remove first count occurrences
              count.times do
                index = list.index(element)
                break unless index

                list.delete_at(index)
                removed += 1
              end
            elsif count < 0
              # Remove last |count| occurrences
              (-count).times do
                index = list.rindex(element)
                break unless index

                list.delete_at(index)
                removed += 1
              end
            else
              # Remove all occurrences
              removed = list.count(element)
              list.delete(element)
            end

            removed
          end
        end

        def lmove(source, destination, wherefrom, whereto)
          @mutex.synchronize do
            return nil if expired?(source)

            source_list = @data[source]
            return nil unless source_list.is_a?(Array) && !source_list.empty?

            @data[destination] = [] unless @data[destination].is_a?(Array)
            dest_list = @data[destination]

            # Pop from source
            element = if wherefrom.upcase == "LEFT"
                        source_list.shift
                      else
                        source_list.pop
                      end

            # Push to destination
            if whereto.upcase == "LEFT"
              dest_list.unshift(element)
            else
              dest_list.push(element)
            end

            element
          end
        end

        # Set operations
        def sadd(key, *members)
          @mutex.synchronize do
            @data[key] = Set.new unless @data[key].is_a?(Set)
            added = 0
            members.each do |member|
              added += 1 if @data[key].add?(member)
            end
            added
          end
        end

        def srem(key, *members)
          @mutex.synchronize do
            return 0 if expired?(key)

            set = @data[key]
            return 0 unless set.is_a?(Set)

            removed = 0
            members.each do |member|
              removed += 1 if set.delete?(member)
            end
            removed
          end
        end

        def scard(key)
          @mutex.synchronize do
            return 0 if expired?(key)

            set = @data[key]
            return 0 unless set.is_a?(Set)

            set.size
          end
        end

        def sismember(key, member)
          @mutex.synchronize do
            return 0 if expired?(key)

            set = @data[key]
            return 0 unless set.is_a?(Set)

            set.include?(member) ? 1 : 0
          end
        end

        def smembers(key)
          @mutex.synchronize do
            return [] if expired?(key)

            set = @data[key]
            return [] unless set.is_a?(Set)

            set.to_a
          end
        end

        # Sorted set operations
        def zadd(key, *score_member_pairs)
          @mutex.synchronize do
            @data[key] = {} unless @data[key].is_a?(Hash)
            added = 0

            score_member_pairs.each_slice(2) do |score, member|
              added += 1 unless @data[key].key?(member)
              @data[key][member] = score.to_f
            end

            added
          end
        end

        def zcard(key)
          @mutex.synchronize do
            return 0 if expired?(key)

            zset = @data[key]
            return 0 unless zset.is_a?(Hash)

            zset.size
          end
        end

        def zincrby(key, increment, member)
          @mutex.synchronize do
            @data[key] = {} unless @data[key].is_a?(Hash)
            current = @data[key][member] || 0.0
            @data[key][member] = current + increment.to_f
            @data[key][member].to_s
          end
        end

        def zrange(key, start, stop, withscores: false)
          @mutex.synchronize do
            return [] if expired?(key)

            zset = @data[key]
            return [] unless zset.is_a?(Hash)

            # Sort by score, then lexicographically by member
            sorted = zset.sort_by { |member, score| [score, member] }

            # Handle negative indices
            start = sorted.size + start if start < 0
            stop = sorted.size + stop if stop < 0

            return [] if start > sorted.size - 1 || start < 0

            stop = sorted.size - 1 if stop >= sorted.size
            return [] if stop < start

            result = sorted[start..stop] || []

            if withscores
              result.flatten
            else
              result.map(&:first)
            end
          end
        end

        def zrem(key, *members)
          @mutex.synchronize do
            return 0 if expired?(key)

            zset = @data[key]
            return 0 unless zset.is_a?(Hash)

            removed = 0
            members.each do |member|
              removed += 1 if zset.delete(member)
            end
            removed
          end
        end

        def zremrangebyrank(key, start, stop)
          @mutex.synchronize do
            return 0 if expired?(key)

            zset = @data[key]
            return 0 unless zset.is_a?(Hash)

            sorted = zset.sort_by { |member, score| [score, member] }

            # Handle negative indices
            start = sorted.size + start if start < 0
            stop = sorted.size + stop if stop < 0

            return 0 if start > sorted.size - 1 || start < 0

            stop = sorted.size - 1 if stop >= sorted.size
            return 0 if stop < start

            to_remove = sorted[start..stop] || []
            to_remove.each { |member, _| zset.delete(member) }
            to_remove.size
          end
        end

        def zremrangebyscore(key, min, max)
          @mutex.synchronize do
            return 0 if expired?(key)

            zset = @data[key]
            return 0 unless zset.is_a?(Hash)

            removed = 0
            zset.each do |member, score|
              if score >= min.to_f && score <= max.to_f
                zset.delete(member)
                removed += 1
              end
            end
            removed
          end
        end

        # Pub/Sub operations
        def publish(_channel, _message)
          # In a real implementation, this would publish to subscribers
          # For testing, we just return 0 (no subscribers)
          0
        end

        # Script operations
        def script_load(script)
          @mutex.synchronize do
            # Generate a simple hash for the script
            digest = script.hash.to_s(16)
            @scripts[digest] = script
            digest
          end
        end

        def script_exists(*digests)
          @mutex.synchronize do
            digests.map { |digest| @scripts.key?(digest) ? 1 : 0 }
          end
        end

        # Bitfield operations (simplified implementation)
        def bitfield(key, *operations)
          @mutex.synchronize do
            @data[key] = "0" unless @data[key].is_a?(String)
            # For simplicity, return array of zeros
            # Real implementation would handle GET, SET, INCRBY operations
            Array.new(operations.count { |op| op.is_a?(Array) && %w[GET SET INCRBY].include?(op[0].upcase) }, 0)
          end
        end

        def bitfield_ro(key, *operations)
          @mutex.synchronize do
            return [] if expired?(key)

            value = @data[key]
            return [] unless value.is_a?(String)

            # For simplicity, return array of zeros for GET operations
            Array.new(operations.count { |op| op.is_a?(Array) && op[0].upcase == "GET" }, 0)
          end
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

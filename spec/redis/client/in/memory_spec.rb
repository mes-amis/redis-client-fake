# frozen_string_literal: true

RSpec.describe Redis::Client::Fake do
  let(:redis_client) { RedisClient.config(driver: :fake).new_client }

  before do
    # Reset storage before each test
    Redis::Client::Fake::Connection.reset_shared_storage!
  end

  after do
    redis_client&.close
  end

  it "has a version number" do
    expect(Redis::Client::Fake::VERSION).not_to be nil
  end

  describe "driver registration" do
    it "registers the fake driver" do
      expect(RedisClient.driver(:fake)).to eq(Redis::Client::Fake::Connection)
    end
  end

  describe "basic operations" do
    it "responds to PING" do
      expect(redis_client.call("PING")).to eq("PONG")
    end

    it "responds to PING with message" do
      expect(redis_client.call("PING", "hello")).to eq("hello")
    end

    it "supports SET and GET" do
      redis_client.call("SET", "key", "value")
      expect(redis_client.call("GET", "key")).to eq("value")
    end

    it "returns nil for non-existent keys" do
      expect(redis_client.call("GET", "nonexistent")).to be_nil
    end

    it "supports EXISTS" do
      redis_client.call("SET", "key", "value")
      expect(redis_client.call("EXISTS", "key")).to eq(1)
      expect(redis_client.call("EXISTS", "nonexistent")).to eq(0)
      expect(redis_client.call("EXISTS", "key", "nonexistent")).to eq(1)
    end

    it "supports DEL" do
      redis_client.call("SET", "key1", "value1")
      redis_client.call("SET", "key2", "value2")
      expect(redis_client.call("DEL", "key1", "key2", "nonexistent")).to eq(2)
      expect(redis_client.call("GET", "key1")).to be_nil
      expect(redis_client.call("GET", "key2")).to be_nil
    end

    it "supports KEYS" do
      redis_client.call("SET", "foo", "1")
      redis_client.call("SET", "bar", "2")
      redis_client.call("SET", "baz", "3")

      keys = redis_client.call("KEYS", "*")
      expect(keys.sort).to eq(%w[foo bar baz].sort)

      keys = redis_client.call("KEYS", "ba*")
      expect(keys.sort).to eq(%w[bar baz].sort)
    end

    it "supports FLUSHALL" do
      redis_client.call("SET", "key", "value")
      expect(redis_client.call("FLUSHALL")).to eq("OK")
      expect(redis_client.call("GET", "key")).to be_nil
    end

    it "supports DBSIZE" do
      expect(redis_client.call("DBSIZE")).to eq(0)
      redis_client.call("SET", "key1", "value1")
      redis_client.call("SET", "key2", "value2")
      expect(redis_client.call("DBSIZE")).to eq(2)
    end
  end

  describe "expiration" do
    it "supports EXPIRE" do
      redis_client.call("SET", "key", "value")
      expect(redis_client.call("EXPIRE", "key", 1)).to eq(1)
      expect(redis_client.call("TTL", "key")).to be_between(0, 1)
    end

    it "supports EXPIREAT" do
      redis_client.call("SET", "key", "value")
      future_timestamp = Time.now.to_i + 1
      expect(redis_client.call("EXPIREAT", "key", future_timestamp)).to eq(1)
      expect(redis_client.call("TTL", "key")).to be_between(0, 1)
    end

    it "supports SET with EX option" do
      redis_client.call("SET", "key", "value", "EX", 1)
      expect(redis_client.call("TTL", "key")).to be_between(0, 1)
    end

    it "returns correct TTL values" do
      redis_client.call("SET", "key", "value")
      expect(redis_client.call("TTL", "key")).to eq(-1) # no expiration
      expect(redis_client.call("TTL", "nonexistent")).to eq(-2) # doesn't exist
    end
  end

  describe "connection behavior" do
    it "maintains connection state" do
      # RedisClient doesn't expose connected? method, but we can test that it works
      expect(redis_client.call("PING")).to eq("PONG")
      redis_client.close
      # After closing, operations should still work due to reconnection
      expect(redis_client.call("PING")).to eq("PONG")
    end

    it "supports pipelined operations" do
      results = redis_client.pipelined do |pipe|
        pipe.call("SET", "key1", "value1")
        pipe.call("SET", "key2", "value2")
        pipe.call("GET", "key1")
        pipe.call("GET", "key2")
      end

      expect(results).to eq(%w[OK OK value1 value2])
    end
  end

  describe "error handling" do
    it "returns error for unknown commands" do
      expect { redis_client.call("UNKNOWN_COMMAND") }.to raise_error(/unknown command/)
    end
  end

  describe "HELLO command" do
    it "responds to HELLO command" do
      result = redis_client.call("HELLO")
      expect(result).to be_an(Array)
      expect(result).to include("server", "redis")
      expect(result).to include("version", "7.0.0-fake")
    end
  end

  describe "string operations" do
    it "supports INCR" do
      expect(redis_client.call("INCR", "counter")).to eq(1)
      expect(redis_client.call("INCR", "counter")).to eq(2)
    end

    it "supports INCRBY" do
      expect(redis_client.call("INCRBY", "counter", 5)).to eq(5)
      expect(redis_client.call("INCRBY", "counter", 3)).to eq(8)
    end

    it "supports MGET and MSET" do
      redis_client.call("MSET", "key1", "value1", "key2", "value2")
      expect(redis_client.call("MGET", "key1", "key2", "key3")).to eq(["value1", "value2", nil])
    end

    it "supports TYPE" do
      expect(redis_client.call("TYPE", "nonexistent")).to eq("none")
      redis_client.call("SET", "string_key", "value")
      expect(redis_client.call("TYPE", "string_key")).to eq("string")
    end

    it "supports UNLINK" do
      redis_client.call("SET", "key1", "value1")
      redis_client.call("SET", "key2", "value2")
      expect(redis_client.call("UNLINK", "key1", "key2")).to eq(2)
    end

    it "supports PTTL" do
      redis_client.call("SET", "key", "value", "EX", 1)
      pttl = redis_client.call("PTTL", "key")
      expect(pttl).to be_between(1, 1000)
      expect(redis_client.call("PTTL", "nonexistent")).to eq(-2)
    end
  end

  describe "hash operations" do
    it "supports HSET and HGET" do
      expect(redis_client.call("HSET", "hash", "field", "value")).to eq(1)
      expect(redis_client.call("HGET", "hash", "field")).to eq("value")
    end

    it "supports HSETNX" do
      expect(redis_client.call("HSETNX", "hash", "field", "value")).to eq(1)
      expect(redis_client.call("HSETNX", "hash", "field", "new_value")).to eq(0)
      expect(redis_client.call("HGET", "hash", "field")).to eq("value")
    end

    it "supports HGETALL" do
      redis_client.call("HSET", "hash", "field1", "value1")
      redis_client.call("HSET", "hash", "field2", "value2")
      result = redis_client.call("HGETALL", "hash")
      expect(result).to include("field1", "value1", "field2", "value2")
    end

    it "supports HDEL" do
      redis_client.call("HSET", "hash", "field1", "value1")
      redis_client.call("HSET", "hash", "field2", "value2")
      expect(redis_client.call("HDEL", "hash", "field1")).to eq(1)
      expect(redis_client.call("HGET", "hash", "field1")).to be_nil
    end

    it "supports HINCRBY" do
      expect(redis_client.call("HINCRBY", "hash", "counter", 5)).to eq(5)
      expect(redis_client.call("HINCRBY", "hash", "counter", 3)).to eq(8)
    end

    it "supports HLEN" do
      expect(redis_client.call("HLEN", "hash")).to eq(0)
      redis_client.call("HSET", "hash", "field1", "value1")
      redis_client.call("HSET", "hash", "field2", "value2")
      expect(redis_client.call("HLEN", "hash")).to eq(2)
    end

    it "supports HMGET" do
      redis_client.call("HSET", "hash", "field1", "value1")
      redis_client.call("HSET", "hash", "field2", "value2")
      expect(redis_client.call("HMGET", "hash", "field1", "field2", "field3")).to eq(["value1", "value2", nil])
    end
  end

  describe "list operations" do
    it "supports LPUSH and RPUSH" do
      expect(redis_client.call("LPUSH", "list", "left")).to eq(1)
      expect(redis_client.call("RPUSH", "list", "right")).to eq(2)
    end

    it "supports LPOP and RPOP" do
      redis_client.call("LPUSH", "list", "first", "second", "third")
      expect(redis_client.call("LPOP", "list")).to eq("third")
      expect(redis_client.call("RPOP", "list")).to eq("first")
    end

    it "supports LLEN" do
      expect(redis_client.call("LLEN", "list")).to eq(0)
      redis_client.call("LPUSH", "list", "item1", "item2")
      expect(redis_client.call("LLEN", "list")).to eq(2)
    end

    it "supports LINDEX" do
      redis_client.call("LPUSH", "list", "first", "second", "third")
      expect(redis_client.call("LINDEX", "list", 0)).to eq("third")
      expect(redis_client.call("LINDEX", "list", -1)).to eq("first")
    end

    it "supports LRANGE" do
      redis_client.call("LPUSH", "list", "c", "b", "a")
      expect(redis_client.call("LRANGE", "list", 0, -1)).to eq(%w[a b c])
      expect(redis_client.call("LRANGE", "list", 0, 1)).to eq(%w[a b])
    end

    it "supports LREM" do
      redis_client.call("RPUSH", "list", "a", "b", "a", "c", "a")
      expect(redis_client.call("LREM", "list", 2, "a")).to eq(2)
      expect(redis_client.call("LRANGE", "list", 0, -1)).to eq(%w[b c a])
    end

    it "supports LMOVE" do
      redis_client.call("RPUSH", "source", "a", "b", "c")
      redis_client.call("RPUSH", "dest", "x", "y")
      result = redis_client.call("LMOVE", "source", "dest", "LEFT", "RIGHT")
      expect(result).to eq("a")
      expect(redis_client.call("LRANGE", "source", 0, -1)).to eq(%w[b c])
      expect(redis_client.call("LRANGE", "dest", 0, -1)).to eq(%w[x y a])
    end
  end

  describe "set operations" do
    it "supports SADD and SCARD" do
      expect(redis_client.call("SADD", "set", "member1", "member2")).to eq(2)
      expect(redis_client.call("SADD", "set", "member1")).to eq(0) # already exists
      expect(redis_client.call("SCARD", "set")).to eq(2)
    end

    it "supports SISMEMBER" do
      redis_client.call("SADD", "set", "member1", "member2")
      expect(redis_client.call("SISMEMBER", "set", "member1")).to eq(1)
      expect(redis_client.call("SISMEMBER", "set", "nonexistent")).to eq(0)
    end

    it "supports SMEMBERS" do
      redis_client.call("SADD", "set", "member1", "member2", "member3")
      members = redis_client.call("SMEMBERS", "set")
      expect(members.sort).to eq(%w[member1 member2 member3].sort)
    end

    it "supports SREM" do
      redis_client.call("SADD", "set", "member1", "member2", "member3")
      expect(redis_client.call("SREM", "set", "member1", "member2")).to eq(2)
      expect(redis_client.call("SCARD", "set")).to eq(1)
    end
  end

  describe "sorted set operations" do
    it "supports ZADD and ZCARD" do
      expect(redis_client.call("ZADD", "zset", 1, "member1", 2, "member2")).to eq(2)
      expect(redis_client.call("ZCARD", "zset")).to eq(2)
    end

    it "supports ZINCRBY" do
      redis_client.call("ZADD", "zset", 1, "member1")
      result = redis_client.call("ZINCRBY", "zset", 2, "member1")
      expect(result).to eq("3.0")
    end

    it "supports ZRANGE" do
      redis_client.call("ZADD", "zset", 3, "c", 1, "a", 2, "b")
      expect(redis_client.call("ZRANGE", "zset", 0, -1)).to eq(%w[a b c])

      result = redis_client.call("ZRANGE", "zset", 0, 1, "WITHSCORES")
      expect(result).to eq(["a", 1.0, "b", 2.0])
    end

    it "supports ZREM" do
      redis_client.call("ZADD", "zset", 1, "member1", 2, "member2")
      expect(redis_client.call("ZREM", "zset", "member1")).to eq(1)
      expect(redis_client.call("ZCARD", "zset")).to eq(1)
    end

    it "supports ZREMRANGEBYRANK" do
      redis_client.call("ZADD", "zset", 1, "a", 2, "b", 3, "c", 4, "d")
      expect(redis_client.call("ZREMRANGEBYRANK", "zset", 1, 2)).to eq(2) # removes b and c
      expect(redis_client.call("ZRANGE", "zset", 0, -1)).to eq(%w[a d])
    end

    it "supports ZREMRANGEBYSCORE" do
      redis_client.call("ZADD", "zset", 1, "a", 2, "b", 3, "c", 4, "d")
      expect(redis_client.call("ZREMRANGEBYSCORE", "zset", 2, 3)).to eq(2) # removes b and c
      expect(redis_client.call("ZRANGE", "zset", 0, -1)).to eq(%w[a d])
    end
  end

  describe "pub/sub operations" do
    it "supports PUBLISH" do
      expect(redis_client.call("PUBLISH", "channel", "message")).to eq(0) # no subscribers
    end
  end

  describe "script operations" do
    it "supports SCRIPT LOAD and SCRIPT EXISTS" do
      script = "return ARGV[1]"
      digest = redis_client.call("SCRIPT", "LOAD", script)
      expect(digest).to be_a(String)

      result = redis_client.call("SCRIPT", "EXISTS", digest, "nonexistent")
      expect(result).to eq([1, 0])
    end
  end

  describe "bitfield operations" do
    it "supports BITFIELD" do
      result = redis_client.call("BITFIELD", "key", ["GET", "i8", 0])
      expect(result).to be_an(Array)
    end

    it "supports BITFIELD_RO" do
      result = redis_client.call("BITFIELD_RO", "key", ["GET", "i8", 0])
      expect(result).to be_an(Array)
    end
  end
end

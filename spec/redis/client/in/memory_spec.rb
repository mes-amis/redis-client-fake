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
end

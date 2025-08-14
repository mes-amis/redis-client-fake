# frozen_string_literal: true

require "redis_client"
require_relative "fake/version"
require_relative "fake/storage"
require_relative "fake/connection"

module Redis
  module Client
    module Fake
      class Error < StandardError; end
    end
  end
end

# Register the fake driver with redis-client
RedisClient.register_driver :fake do
  Redis::Client::Fake::Connection
end

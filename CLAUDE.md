# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby gem called `redis-client-fake` that provides an in-memory backend for the redis-client gem, similar to Fakeredis. The gem uses the module name `Redis::Client::Fake` and is in early development stage with a basic module structure but minimal implementation.

## Development Commands

### Setup
- `bin/setup` - Install dependencies via bundle install
- `bin/console` - Start an interactive IRB session with the gem loaded

### Testing
- `rake spec` - Run RSpec tests
- `bundle exec rspec` - Run tests directly with RSpec

### Linting and Code Quality  
- `rake rubocop` - Run RuboCop linter
- `bundle exec rubocop` - Run RuboCop directly
- `rake` - Run both specs and RuboCop (default task)

### Gem Management
- `bundle exec rake install` - Install gem locally
- `bundle exec rake release` - Release new version (updates version, creates git tag, pushes to RubyGems)

## Code Architecture

### Module Structure
The gem follows Ruby gem conventions with nested modules:
- `Redis::Client::Fake` - Main module namespace (renamed from In::Memory)
- `Redis::Client::Fake::Error` - Custom error class
- `Redis::Client::Fake::VERSION` - Version constant

### File Organization
- `lib/redis/client/fake.rb` - Main entry point, currently contains only module structure and error class
- `lib/redis/client/fake/version.rb` - Version definition
- `spec/redis/client/in/memory_spec.rb` - RSpec tests (uses Fake module)
- `sig/redis/client/fake.rbs` - RBS type signatures

### Configuration
- `.rubocop.yml` - RuboCop configuration with double quotes enforced and 120 character line length
- Target Ruby version: 2.6+
- Uses RSpec for testing with monkey patching disabled
- Includes RBS type signatures in `sig/` directory

### Dependencies
- Development dependencies: rake, rspec, rubocop
- No runtime dependencies currently defined
- Uses Bundler for dependency management

## Current State
The gem provides a fully functional in-memory Redis driver registered as `:fake` with redis-client. It implements:

### Supported Redis Commands
- **Connection**: PING, HELLO
- **Key operations**: GET, SET (with expiration options), EXISTS, DEL, KEYS, TTL, EXPIRE, EXPIREAT
- **Database**: FLUSHALL, FLUSHDB, DBSIZE
- **Advanced features**: Pipelined operations, transactions via MULTI/EXEC

### Architecture
- **Thread-safe storage**: `Redis::Client::Fake::Storage` with mutex-based synchronization
- **Driver implementation**: `Redis::Client::Fake::Connection` that implements redis-client's connection protocol
- **Automatic registration**: Driver registers as `:fake` when redis-client is available
- **Shared storage**: Multiple connections share the same in-memory data store
- **Full compatibility**: Works with all redis-client features including pipelining

### Usage
```ruby
require 'redis/client/fake'

# Create client with fake driver
client = RedisClient.config(driver: :fake).new_client

# Use like any Redis client
client.call("SET", "key", "value")
client.call("GET", "key") # => "value"

# Supports pipelining
results = client.pipelined do |pipe|
  pipe.call("SET", "key1", "value1")
  pipe.call("GET", "key1")
end
```
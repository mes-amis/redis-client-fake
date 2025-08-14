# frozen_string_literal: true

RSpec.describe Redis::Client::Fake do
  it "has a version number" do
    expect(Redis::Client::Fake::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end

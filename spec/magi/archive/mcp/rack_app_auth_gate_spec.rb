# frozen_string_literal: true

require "spec_helper"
require "magi/archive/mcp/rack_app"

# Security regression test for the 2026-06-14 incident:
# the hosted MCP server served no-token requests through a privileged DEFAULT
# identity, so anyone could read restricted/GM cards without logging in. Two
# enablers: (1) the "localhost bypass" fired for proxied/external requests
# because nginx forwarded a localhost Host header; (2) no-token requests were
# dispatched instead of rejected.
#
# These tests lock in the gate behaviour at the code level. (A deployment-level
# check — which also catches nginx Host misconfig — lives in
# scripts/smoke_test_auth_gate.sh.)
RSpec.describe Magi::Archive::Mcp::RackApp, "unauthenticated access gate" do
  let(:mock_mcp_server) do
    instance_double("MCP::Server", tools: [], server_context: {}, "server_context=": nil,
                                   handle: { jsonrpc: "2.0", id: 1, result: {} })
  end
  let(:app) { described_class.new }

  before do
    described_class.mcp_server_instance = mock_mcp_server
    # oauth_enabled? == token_issuer && credential_store && client_cards
    described_class.token_issuer = instance_double("TokenIssuer")
    described_class.credential_store = instance_double("CredentialStore")
    described_class.client_cards = instance_double("ClientCards")
    described_class.rate_limiter = nil
    described_class.instance_variable_set(:@session_manager, nil)
  end

  around do |example|
    orig = ENV["OAUTH_REQUIRE_AUTH"]
    ENV["OAUTH_REQUIRE_AUTH"] = "true"
    example.run
    ENV["OAUTH_REQUIRE_AUTH"] = orig
  end

  def mcp_request(host:, token: nil)
    env = {
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/",
      "HTTP_HOST" => host,
      "CONTENT_TYPE" => "application/json",
      "rack.input" => StringIO.new('{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    }
    env["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    app.call(env)
  end

  describe ".localhost_origin?" do
    it "does NOT treat an external/proxied host as local (the root of the breach)" do
      expect(described_class.localhost_origin?("HTTP_HOST" => "mcp.magi-agi.org")).to be false
      expect(described_class.localhost_origin?("HTTP_HOST" => "wiki.example.com")).to be false
    end

    it "treats only genuine localhost as local" do
      expect(described_class.localhost_origin?("HTTP_HOST" => "127.0.0.1:3002")).to be true
      expect(described_class.localhost_origin?("HTTP_HOST" => "localhost:3002")).to be true
      expect(described_class.localhost_origin?("HTTP_HOST" => "127.0.0.1")).to be true
    end
  end

  it "rejects a no-token MCP request from an external host with 401" do
    status, = mcp_request(host: "mcp.magi-agi.org")
    expect(status).to eq(401)
  end

  it "still permits the same-box localhost bypass for trusted same-machine callers" do
    status, = mcp_request(host: "127.0.0.1:3002")
    expect(status).not_to eq(401)
  end
end

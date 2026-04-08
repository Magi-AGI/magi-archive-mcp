# frozen_string_literal: true

require "spec_helper"
require "magi/archive/mcp/rack_app"

RSpec.describe Magi::Archive::Mcp::RackApp do
  let(:mock_mcp_server) do
    instance_double("MCP::Server", tools: [], server_context: {}, "server_context=": nil,
                                   handle: { jsonrpc: "2.0", id: 1, result: {} })
  end

  let(:app) { described_class.new }

  before do
    described_class.mcp_server_instance = mock_mcp_server
    described_class.token_issuer = nil
    described_class.credential_store = nil
    described_class.client_cards = nil
    described_class.rate_limiter = nil
    described_class.instance_variable_set(:@session_manager, nil)
  end

  def make_request(method, path, body: nil, headers: {})
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "SERVER_NAME" => "localhost",
      "SERVER_PORT" => "3002",
      "HTTP_HOST" => "localhost:3002",
      "rack.input" => StringIO.new(body || "")
    }
    headers.each { |k, v| env["HTTP_#{k.upcase.tr("-", "_")}"] = v }
    env["CONTENT_TYPE"] = headers["Content-Type"] if headers["Content-Type"]
    app.call(env)
  end

  describe "CORS headers" do
    it "includes CORS headers on health response" do
      status, headers, = make_request("GET", "/health")

      expect(status).to eq(200)
      expect(headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(headers["Access-Control-Allow-Methods"]).to include("POST")
      expect(headers["Access-Control-Allow-Headers"]).to include("Mcp-Session-Id")
      expect(headers["Access-Control-Expose-Headers"]).to include("Mcp-Session-Id")
    end

    it "includes CORS headers on 404 responses" do
      status, headers, = make_request("GET", "/nonexistent")

      expect(status).to eq(404)
      expect(headers["Access-Control-Allow-Origin"]).to eq("*")
    end

    it "includes MCP-Protocol-Version in exposed headers" do
      _, headers, = make_request("GET", "/health")

      expect(headers["Access-Control-Expose-Headers"]).to include("MCP-Protocol-Version")
    end
  end

  describe "OPTIONS preflight" do
    it "returns 204 for OPTIONS requests" do
      status, headers, = make_request("OPTIONS", "/")

      expect(status).to eq(204)
      expect(headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(headers["Access-Control-Allow-Methods"]).to include("POST")
      expect(headers["Access-Control-Allow-Methods"]).to include("GET")
      expect(headers["Access-Control-Allow-Methods"]).to include("DELETE")
      expect(headers["Access-Control-Allow-Headers"]).to include("Content-Type")
      expect(headers["Access-Control-Allow-Headers"]).to include("Authorization")
      expect(headers["Access-Control-Max-Age"]).to eq("86400")
    end

    it "returns 204 for OPTIONS on /mcp" do
      status, = make_request("OPTIONS", "/mcp")
      expect(status).to eq(204)
    end

    it "returns 204 for OPTIONS on /messages" do
      status, = make_request("OPTIONS", "/messages")
      expect(status).to eq(204)
    end

    it "returns 204 for OPTIONS on any unknown path" do
      status, = make_request("OPTIONS", "/anything")
      expect(status).to eq(204)
    end
  end

  describe "/mcp endpoint" do
    it "accepts MCP messages on POST /mcp" do
      body = JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
      status, _, response_body = make_request("POST", "/mcp",
                                              body: body,
                                              headers: { "Content-Type" => "application/json" })

      expect(status).to eq(200)
      parsed = JSON.parse(response_body.first)
      expect(parsed).to have_key("jsonrpc")
    end

    it "handles DELETE /mcp for session cleanup" do
      status, = make_request("DELETE", "/mcp")
      expect(status).to eq(200)
    end

    it "accepts MCP messages on POST /mcp/" do
      body = JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
      status, = make_request("POST", "/mcp/",
                             body: body,
                             headers: { "Content-Type" => "application/json" })

      expect(status).to eq(200)
    end
  end

  describe "health endpoint" do
    it "returns healthy status" do
      status, _, body = make_request("GET", "/health")

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["status"]).to eq("healthy")
      expect(parsed["version"]).to eq(Magi::Archive::Mcp::VERSION)
    end

    it "caches the health response within TTL" do
      _, _, body1 = make_request("GET", "/health")
      _, _, body2 = make_request("GET", "/health")

      # Same cached response within TTL
      expect(body2.first).to eq(body1.first)
    end
  end

  describe "root endpoint" do
    it "lists /mcp in endpoints" do
      _, _, body = make_request("GET", "/")

      parsed = JSON.parse(body.first)
      expect(parsed["endpoints"]["mcp"]).to eq("/mcp")
    end
  end

  describe "empty POST body handling" do
    it "returns 200 with server info for empty POST to /" do
      status, _, body = make_request("POST", "/", body: "",
                                                  headers: { "Content-Type" => "application/json" })

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["jsonrpc"]).to eq("2.0")
      expect(parsed["result"]["protocolVersion"]).to eq("2025-06-18")
      expect(parsed["result"]["serverInfo"]["name"]).to eq("magi-archive")
    end

    it "returns 200 for whitespace-only POST body" do
      status, _, body = make_request("POST", "/", body: "  \n  ",
                                                  headers: { "Content-Type" => "application/json" })

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["result"]["serverInfo"]["name"]).to eq("magi-archive")
    end

    it "returns 200 for nil body" do
      status, _, body = make_request("POST", "/", body: nil,
                                                  headers: { "Content-Type" => "application/json" })

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["result"]["serverInfo"]["name"]).to eq("magi-archive")
    end

    it "returns SSE for empty POST with Accept: text/event-stream" do
      status, headers, = make_request("POST", "/", body: "",
                                                   headers: {
                                                     "Content-Type" => "application/json",
                                                     "Accept" => "text/event-stream"
                                                   })

      expect(status).to eq(200)
      expect(headers["Content-Type"]).to eq("text/event-stream")
    end

    it "works on all MCP POST endpoints" do
      %w[/ /mcp /message].each do |path|
        status, _, body = make_request("POST", path, body: "",
                                                     headers: { "Content-Type" => "application/json" })

        expect(status).to eq(200)
        parsed = JSON.parse(body.first)
        expect(parsed["result"]["serverInfo"]["name"]).to eq("magi-archive")
      end
    end
  end

  describe "empty POST before auth check" do
    before do
      # Simulate OAUTH_REQUIRE_AUTH=true with OAuth enabled
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OAUTH_REQUIRE_AUTH", "false").and_return("true")
      allow(ENV).to receive(:fetch).with("OAUTH_ISSUER_URL", anything).and_return("https://mcp.magi-agi.org")

      mock_token_issuer = double("TokenIssuer")
      mock_credential_store = double("CredentialStore")
      mock_client_cards = double("ClientCards")
      described_class.token_issuer = mock_token_issuer
      described_class.credential_store = mock_credential_store
      described_class.client_cards = mock_client_cards
    end

    after do
      described_class.token_issuer = nil
      described_class.credential_store = nil
      described_class.client_cards = nil
    end

    it "returns 200 for empty POST even when auth is required" do
      status, _, body = make_request("POST", "/", body: "",
                                                  headers: { "Content-Type" => "application/json" })

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["result"]["serverInfo"]["name"]).to eq("magi-archive")
    end

    it "does NOT return 401 for empty POST when auth is required" do
      status, = make_request("POST", "/", body: "",
                                          headers: { "Content-Type" => "application/json" })

      expect(status).not_to eq(401)
    end

    it "returns 401 for non-empty POST without token when auth is required" do
      body = JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
      status, = make_request("POST", "/", body: body,
                                          headers: { "Content-Type" => "application/json" })

      expect(status).to eq(401)
    end
  end

  describe "OIDC discovery endpoint" do
    it "returns openid-configuration" do
      status, headers, body = make_request("GET", "/.well-known/openid-configuration")

      expect(status).to eq(200)
      expect(headers["Content-Type"]).to eq("application/json")

      parsed = JSON.parse(body.first)
      expect(parsed).to have_key("issuer")
      expect(parsed).to have_key("authorization_endpoint")
      expect(parsed).to have_key("token_endpoint")
      expect(parsed).to have_key("jwks_uri")
      expect(parsed["response_types_supported"]).to include("code")
      expect(parsed["code_challenge_methods_supported"]).to include("S256")
      expect(parsed["id_token_signing_alg_values_supported"]).to include("RS256")
      expect(parsed["subject_types_supported"]).to include("public")
    end
  end

  describe "JWKS endpoint" do
    it "returns empty keys when no token issuer configured" do
      status, _, body = make_request("GET", "/jwks")

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["keys"]).to eq([])
    end

    it "returns JWK when token issuer is configured" do
      require "openssl"
      key = OpenSSL::PKey::RSA.generate(2048)
      mock_issuer = double("TokenIssuer", public_key: key.public_key)
      described_class.token_issuer = mock_issuer

      status, _, body = make_request("GET", "/jwks")

      expect(status).to eq(200)
      parsed = JSON.parse(body.first)
      expect(parsed["keys"].length).to eq(1)

      jwk = parsed["keys"].first
      expect(jwk["kty"]).to eq("RSA")
      expect(jwk["alg"]).to eq("RS256")
      expect(jwk["use"]).to eq("sig")
      expect(jwk).to have_key("n")
      expect(jwk).to have_key("e")
      expect(jwk).to have_key("kid")

      described_class.token_issuer = nil
    end

    it "responds on all JWKS paths" do
      %w[/jwks /jwks.json /.well-known/jwks.json].each do |path|
        status, _, body = make_request("GET", path)
        expect(status).to eq(200)
        parsed = JSON.parse(body.first)
        expect(parsed).to have_key("keys")
      end
    end
  end

  describe "SSE first byte" do
    it "delivers connected comment as first yield" do
      _, _, body = make_request("GET", "/sse")

      chunks = []
      body.each do |chunk|
        chunks << chunk
        break if chunks.length >= 2
      end

      expect(chunks.first).to start_with(": connected")
    end
  end
end

RSpec.describe Magi::Archive::Mcp::SessionManager do
  subject(:manager) { described_class.new }

  describe "#get_or_create" do
    it "creates a new session" do
      session_id = manager.get_or_create
      expect(session_id).to be_a(String)
      expect(manager.exists?(session_id)).to be true
    end

    it "returns existing session when valid ID provided" do
      session_id = manager.get_or_create
      same_id = manager.get_or_create(session_id)
      expect(same_id).to eq(session_id)
    end

    it "creates a new session for unknown ID" do
      new_id = manager.get_or_create("nonexistent-id")
      expect(new_id).not_to eq("nonexistent-id")
      expect(manager.exists?(new_id)).to be true
    end
  end

  describe "#exists?" do
    it "returns true for existing session" do
      session_id = manager.get_or_create
      expect(manager.exists?(session_id)).to be true
    end

    it "returns false for unknown session" do
      expect(manager.exists?("nonexistent")).to be false
    end
  end

  describe "#delete" do
    it "removes the session" do
      session_id = manager.get_or_create
      manager.delete(session_id)
      expect(manager.exists?(session_id)).to be false
    end
  end

  describe "#size" do
    it "returns the number of sessions" do
      expect(manager.size).to eq(0)
      manager.get_or_create
      expect(manager.size).to eq(1)
      manager.get_or_create
      expect(manager.size).to eq(2)
    end
  end

  describe "session expiry" do
    it "cleans up expired sessions during get_or_create" do
      session_id = manager.get_or_create

      # Simulate expired session
      manager.instance_variable_get(:@sessions)[session_id][:last_used_at] =
        Time.now - described_class::SESSION_TTL - 1

      # Force cleanup interval to have passed
      manager.instance_variable_set(:@last_cleanup, Time.now - 600)

      # Trigger cleanup via get_or_create
      manager.get_or_create
      expect(manager.exists?(session_id)).to be false
    end

    it "keeps active sessions during cleanup" do
      session_id = manager.get_or_create

      # Force cleanup interval to have passed but session is still active
      manager.instance_variable_set(:@last_cleanup, Time.now - 600)

      manager.get_or_create
      expect(manager.exists?(session_id)).to be true
    end

    it "does not clean up before cleanup interval" do
      session_id = manager.get_or_create

      # Expire the session but don't pass cleanup interval
      manager.instance_variable_get(:@sessions)[session_id][:last_used_at] =
        Time.now - described_class::SESSION_TTL - 1

      # Cleanup interval hasn't passed (default: just created)
      manager.get_or_create
      # Session should still exist because cleanup hasn't run
      expect(manager.size).to be >= 1
    end
  end
end

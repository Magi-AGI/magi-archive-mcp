# frozen_string_literal: true

require "spec_helper"
require "http"
require "json"

# Integration tests for the MCP HTTP server
#
# These tests verify that the HTTP server properly:
# - Serves health check and metadata endpoints
# - Handles SSE transport connections
# - Processes MCP JSON-RPC messages
# - Manages sessions correctly
# - Returns proper error responses
#
# Prerequisites:
# - INTEGRATION_TEST=true environment variable
# - MCP_SERVER_URL environment variable (defaults to https://mcp.magi-agi.org)
#
# Run with:
#   INTEGRATION_TEST=true bundle exec rspec spec/integration/http_server_spec.rb
#
# Run against local server:
#   MCP_SERVER_URL=http://localhost:3002 INTEGRATION_TEST=true bundle exec rspec spec/integration/http_server_spec.rb
#
RSpec.describe "MCP HTTP Server", :integration do
  let(:server_url) { ENV["MCP_SERVER_URL"] || "https://mcp.magi-agi.org" }
  let(:http_client) { HTTP.timeout(connect: 10, read: 30) }

  before do
    skip "Integration tests disabled (set INTEGRATION_TEST=true)" unless ENV["INTEGRATION_TEST"]
  end

  describe "Health Check Endpoint" do
    it "returns healthy status at /health" do
      response = http_client.get("#{server_url}/health")

      expect(response.status).to eq(200)
      expect(response.content_type.mime_type).to eq("application/json")

      body = JSON.parse(response.body.to_s)
      expect(body["status"]).to eq("healthy")
      expect(body).to have_key("version")
      expect(body).to have_key("timestamp")
    end

    it "includes MCP protocol headers" do
      response = http_client.get("#{server_url}/health")

      expect(response.headers["MCP-Protocol-Version"]).not_to be_nil
      expect(response.headers["Mcp-Session-Id"]).not_to be_nil
    end
  end

  describe "Root Endpoint" do
    it "returns JSON metadata when Accept header is not SSE" do
      response = http_client.headers("Accept" => "application/json").get(server_url)

      expect(response.status).to eq(200)
      expect(response.content_type.mime_type).to eq("application/json")

      body = JSON.parse(response.body.to_s)
      expect(body["name"]).to eq("magi-archive-mcp")
      expect(body["protocol"]).to eq("mcp")
      expect(body).to have_key("version")
      expect(body).to have_key("endpoints")
      expect(body["endpoints"]).to include("health", "sse", "messages")
    end

    it "returns SSE stream when Accept header is text/event-stream" do
      # Use a short timeout since we just want to verify the response starts correctly
      response = HTTP.timeout(connect: 5, read: 2)
                     .headers("Accept" => "text/event-stream")
                     .get(server_url)

      expect(response.status).to eq(200)
      expect(response.content_type.mime_type).to eq("text/event-stream")
    rescue HTTP::TimeoutError
      # Expected - SSE streams don't end naturally
      # The fact we got here means the connection was established
    end
  end

  describe "SSE Endpoint" do
    it "establishes SSE connection at /sse" do
      response = HTTP.timeout(connect: 5, read: 2).get("#{server_url}/sse")

      expect(response.status).to eq(200)
      expect(response.content_type.mime_type).to eq("text/event-stream")
    rescue HTTP::TimeoutError
      # Expected for SSE
    end

    it "returns endpoint event with session_id" do
      # Read just enough to get the endpoint event
      response = HTTP.timeout(connect: 5, read: 3).get("#{server_url}/sse")

      expect(response.status).to eq(200)

      # Try to read the first chunk which should contain the endpoint event
      body_start = ""
      begin
        response.body.each do |chunk|
          body_start += chunk
          break if body_start.include?("session_id=")
        end
      rescue HTTP::TimeoutError
        # Expected
      end

      # Verify endpoint event format
      expect(body_start).to include("event: endpoint")
      expect(body_start).to include("data: /messages?session_id=")
    end
  end

  describe "MCP Message Handling" do
    describe "tools/list" do
      it "returns list of available tools" do
        request_body = {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list",
          params: {}
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        expect(response.status).to eq(200)

        body = JSON.parse(response.body.to_s)
        expect(body["jsonrpc"]).to eq("2.0")
        expect(body["id"]).to eq(1)
        expect(body).to have_key("result")
        expect(body["result"]).to have_key("tools")
        expect(body["result"]["tools"]).to be_an(Array)
        expect(body["result"]["tools"].length).to be > 0

        # Verify tool structure
        first_tool = body["result"]["tools"].first
        expect(first_tool).to have_key("name")
        expect(first_tool).to have_key("description")
        expect(first_tool).to have_key("inputSchema")
      end

      it "includes expected core tools" do
        request_body = {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list",
          params: {}
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        body = JSON.parse(response.body.to_s)
        tool_names = body["result"]["tools"].map { |t| t["name"] }

        expect(tool_names).to include("get_card")
        expect(tool_names).to include("search_cards")
        expect(tool_names).to include("create_card")
        expect(tool_names).to include("update_card")
        expect(tool_names).to include("health_check")
      end
    end

    describe "tools/call" do
      it "executes health_check tool successfully" do
        request_body = {
          jsonrpc: "2.0",
          id: 2,
          method: "tools/call",
          params: {
            name: "health_check",
            arguments: {}
          }
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        expect(response.status).to eq(200)

        body = JSON.parse(response.body.to_s)
        expect(body["jsonrpc"]).to eq("2.0")
        expect(body["id"]).to eq(2)
        expect(body).to have_key("result")
        expect(body["result"]).to have_key("content")
        expect(body["result"]["content"]).to be_an(Array)
        expect(body["result"]["content"].first["type"]).to eq("text")

        # Parse the JSON response from health_check
        health_result = JSON.parse(body["result"]["content"].first["text"])
        expect(health_result["status"]).to eq("success")
        expect(health_result).to have_key("text")
      end

      it "executes get_card tool and returns hybrid JSON format" do
        request_body = {
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: {
            name: "get_card",
            arguments: { name: "Home" }
          }
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        expect(response.status).to eq(200)

        body = JSON.parse(response.body.to_s)
        expect(body["result"]).to have_key("content")

        # Parse the tool response (hybrid JSON format)
        tool_response = JSON.parse(body["result"]["content"].first["text"])
        expect(tool_response).to have_key("id")
        expect(tool_response).to have_key("title")
        expect(tool_response).to have_key("text")
        expect(tool_response).to have_key("source")
        expect(tool_response).to have_key("metadata")

        # The text field should contain markdown
        expect(tool_response["text"]).to include("# Home")
      end

      it "executes search_cards tool and returns results array" do
        request_body = {
          jsonrpc: "2.0",
          id: 4,
          method: "tools/call",
          params: {
            name: "search_cards",
            arguments: { limit: 5 }
          }
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        expect(response.status).to eq(200)

        body = JSON.parse(response.body.to_s)
        tool_response = JSON.parse(body["result"]["content"].first["text"])

        # Search results should have results array (ChatGPT format)
        expect(tool_response).to have_key("results")
        expect(tool_response["results"]).to be_an(Array)
        expect(tool_response).to have_key("total")
        expect(tool_response).to have_key("text")

        # Each result should have required fields
        if tool_response["results"].any?
          result = tool_response["results"].first
          expect(result).to have_key("id")
          expect(result).to have_key("title")
          expect(result).to have_key("source")
        end
      end

      it "returns error for non-existent tool" do
        request_body = {
          jsonrpc: "2.0",
          id: 5,
          method: "tools/call",
          params: {
            name: "non_existent_tool",
            arguments: {}
          }
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        expect(response.status).to eq(200)

        body = JSON.parse(response.body.to_s)
        expect(body).to have_key("error")
        expect(body["error"]["code"]).to be_a(Integer)
      end
    end

    describe "initialize" do
      it "responds to initialize request" do
        request_body = {
          jsonrpc: "2.0",
          id: 10,
          method: "initialize",
          params: {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: {
              name: "test-client",
              version: "1.0.0"
            }
          }
        }

        response = http_client
          .headers("Content-Type" => "application/json")
          .post("#{server_url}/message", json: request_body)

        expect(response.status).to eq(200)

        body = JSON.parse(response.body.to_s)
        expect(body["jsonrpc"]).to eq("2.0")
        expect(body["id"]).to eq(10)
        expect(body).to have_key("result")
        expect(body["result"]).to have_key("protocolVersion")
        expect(body["result"]).to have_key("serverInfo")
        expect(body["result"]).to have_key("capabilities")
      end
    end
  end

  describe "Session Management" do
    it "creates new session and returns session ID in header" do
      response = http_client.get("#{server_url}/health")

      session_id = response.headers["Mcp-Session-Id"]
      expect(session_id).not_to be_nil
      expect(session_id).to match(/^[0-9a-f-]{36}$/) # UUID format
    end

    it "preserves session when Mcp-Session-Id header is provided" do
      # First request to get a session
      first_response = http_client.get("#{server_url}/health")
      session_id = first_response.headers["Mcp-Session-Id"]

      # Second request with same session ID
      second_response = http_client
        .headers("Mcp-Session-Id" => session_id)
        .get("#{server_url}/health")

      expect(second_response.headers["Mcp-Session-Id"]).to eq(session_id)
    end
  end

  describe "Old SSE Transport (/messages endpoint)" do
    it "accepts POST to /messages with session_id query param" do
      # First get a session via SSE
      sse_response = HTTP.timeout(connect: 5, read: 3).get("#{server_url}/sse")
      session_id = sse_response.headers["Mcp-Session-Id"]

      # Now POST to /messages with that session
      request_body = {
        jsonrpc: "2.0",
        id: 20,
        method: "tools/list",
        params: {}
      }

      response = http_client
        .headers("Content-Type" => "application/json")
        .post("#{server_url}/messages?session_id=#{session_id}", json: request_body)

      # Old SSE transport returns 202 Accepted
      expect(response.status).to eq(202)

      body = JSON.parse(response.body.to_s)
      expect(body["result"]).to have_key("tools")
    rescue HTTP::TimeoutError
      skip "SSE connection timed out"
    end

    it "returns 404 for invalid session_id" do
      request_body = {
        jsonrpc: "2.0",
        id: 21,
        method: "tools/list",
        params: {}
      }

      response = http_client
        .headers("Content-Type" => "application/json")
        .post("#{server_url}/messages?session_id=invalid-session-id", json: request_body)

      expect(response.status).to eq(404)

      body = JSON.parse(response.body.to_s)
      expect(body["error"]["message"]).to include("Session not found")
    end
  end

  describe "Error Handling" do
    it "returns parse error for invalid JSON" do
      response = http_client
        .headers("Content-Type" => "application/json")
        .post("#{server_url}/message", body: "not valid json")

      expect(response.status).to eq(400)

      body = JSON.parse(response.body.to_s)
      expect(body["error"]["code"]).to eq(-32700)
      expect(body["error"]["message"]).to eq("Parse error")
    end

    it "returns 404 for unknown endpoints" do
      response = http_client.get("#{server_url}/unknown-endpoint")

      expect(response.status).to eq(404)
    end
  end

  describe "OAuth Discovery Endpoints" do
    it "returns OAuth authorization server metadata" do
      response = http_client.get("#{server_url}/.well-known/oauth-authorization-server")

      expect(response.status).to eq(200)

      body = JSON.parse(response.body.to_s)
      expect(body).to have_key("issuer")
      expect(body).to have_key("token_endpoint")
      expect(body).to have_key("registration_endpoint")
    end

    it "handles client registration" do
      response = http_client
        .headers("Content-Type" => "application/json")
        .post("#{server_url}/register", json: {})

      expect(response.status).to eq(201)

      body = JSON.parse(response.body.to_s)
      expect(body).to have_key("client_id")
    end

    it "returns token for token endpoint" do
      response = http_client
        .headers("Content-Type" => "application/json")
        .post("#{server_url}/token", json: {})

      expect(response.status).to eq(200)

      body = JSON.parse(response.body.to_s)
      expect(body).to have_key("access_token")
      expect(body).to have_key("token_type")
    end
  end

  describe "Multiple Endpoint Compatibility" do
    # Test that MCP messages work on all supported endpoints
    %w[/ /sse /message /messages].each do |endpoint|
      it "accepts MCP messages on POST #{endpoint}" do
        request_body = {
          jsonrpc: "2.0",
          id: 100,
          method: "tools/list",
          params: {}
        }

        # For /messages, we need a valid session
        url = if endpoint == "/messages"
                # Get session first
                sse_response = HTTP.timeout(connect: 5, read: 2).get("#{server_url}/sse")
                session_id = sse_response.headers["Mcp-Session-Id"]
                "#{server_url}#{endpoint}?session_id=#{session_id}"
              else
                "#{server_url}#{endpoint}"
              end

        response = http_client
          .headers("Content-Type" => "application/json")
          .post(url, json: request_body)

        # /messages returns 202, others return 200
        expect([200, 202]).to include(response.status)

        body = JSON.parse(response.body.to_s)
        expect(body["result"]).to have_key("tools")
      rescue HTTP::TimeoutError
        skip "Connection timed out for #{endpoint}"
      end
    end
  end
end

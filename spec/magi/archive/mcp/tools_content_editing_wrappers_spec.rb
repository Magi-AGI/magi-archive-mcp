# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "magi/archive/mcp/tools"

# Load MCP server tool classes
Dir[File.join(__dir__, '../../../../lib/magi/archive/mcp/server/tools/**/*.rb')].sort.each { |f| require f }

RSpec.describe "Content Editing MCP Tool Wrappers" do
  let(:config) do
    ENV["MCP_API_KEY"] = "test-api-key"
    ENV["DECKO_API_BASE_URL"] = "https://test.example.com/api/mcp"
    ENV["MCP_ROLE"] = "user"
    Magi::Archive::Mcp::Config.new
  end

  let(:client) { Magi::Archive::Mcp::Client.new(config) }
  let(:magi_tools) { Magi::Archive::Mcp::Tools.new(client) }
  let(:server_context) { { magi_tools: magi_tools } }
  let(:valid_token) { "test-jwt-token" }

  let(:card_response) do
    {
      "name" => "Test Card",
      "content" => "updated content",
      "type" => "RichText",
      "id" => 42,
      "updated_at" => "2026-04-07T12:00:00Z",
      "created_at" => "2026-04-01T12:00:00Z"
    }
  end

  before do
    stub_request(:post, "https://test.example.com/api/mcp/auth")
      .to_return(
        status: 201,
        body: { "token" => valid_token, "role" => "user", "expires_in" => 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe Magi::Archive::Mcp::Server::Tools::AppendContent do
    it "returns success response on append" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .to_return(status: 200, body: card_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Test Card",
        content: "<p>New paragraph</p>",
        separator: "\n",
        server_context: server_context
      )

      expect(response).to be_a(::MCP::Tool::Response)
      json = JSON.parse(response.content.first[:text])
      expect(json["status"]).to eq("success")
      expect(json["text"]).to include("appended")
    end

    it "returns error for nonexistent card" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Missing")
        .to_return(status: 404, body: { "error" => "not_found", "message" => "Card not found" }.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Missing",
        content: "text",
        server_context: server_context
      )

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Not Found")
    end
  end

  describe Magi::Archive::Mcp::Server::Tools::PrependContent do
    it "returns success response on prepend" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .to_return(status: 200, body: card_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Test Card",
        content: "<h1>Title</h1>",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["status"]).to eq("success")
      expect(json["text"]).to include("prepended")
    end
  end

  describe Magi::Archive::Mcp::Server::Tools::FindAndReplace do
    it "returns success with replacement details" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .to_return(status: 200, body: card_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Test Card",
        find: "old text",
        replace: "new text",
        occurrence: "all",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["status"]).to eq("success")
      expect(json["text"]).to include("all occurrences")
      expect(json["metadata"]["occurrence"]).to eq("all")
    end

    it "returns validation error when text not found" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .to_return(
          status: 422,
          body: { "error" => "validation_error", "message" => "Text not found in card content" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      response = described_class.call(
        name: "Test Card",
        find: "nonexistent",
        replace: "new",
        server_context: server_context
      )

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Validation Error")
    end

    it "defaults occurrence to first" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with { |req|
          body = JSON.parse(req.body)
          body["patch"]["occurrence"] == "first"
        }
        .to_return(status: 200, body: card_response.to_json, headers: { "Content-Type" => "application/json" })

      described_class.call(
        name: "Test Card",
        find: "x",
        replace: "y",
        server_context: server_context
      )
    end
  end

  describe Magi::Archive::Mcp::Server::Tools::FindInCard do
    let(:search_response) do
      {
        "card" => "Test Card",
        "query" => "hello",
        "match_count" => 2,
        "content_length" => 500,
        "matches" => [
          { "position" => 10, "context" => "...say hello world...", "context_start" => 0, "match_offset_in_context" => 10 },
          { "position" => 200, "context" => "...another hello here...", "context_start" => 190, "match_offset_in_context" => 10 }
        ]
      }
    end

    it "formats search results with match excerpts" do
      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/search_content")
        .with(query: { "query" => "hello", "context_chars" => "100" })
        .to_return(status: 200, body: search_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Test Card",
        query: "hello",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["text"]).to include("Match 1")
      expect(json["text"]).to include("Match 2")
      expect(json["text"]).to include("hello world")
      expect(json["metadata"]["match_count"]).to eq(2)
    end

    it "handles zero matches gracefully" do
      empty_response = {
        "card" => "Test Card",
        "query" => "zzz",
        "match_count" => 0,
        "content_length" => 500,
        "matches" => []
      }

      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/search_content")
        .with(query: { "query" => "zzz", "context_chars" => "100" })
        .to_return(status: 200, body: empty_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Test Card",
        query: "zzz",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["text"]).to include("No matches found")
      expect(json["metadata"]["match_count"]).to eq(0)
    end
  end

  describe Magi::Archive::Mcp::Server::Tools::GetCardOutline do
    let(:outline_response) do
      {
        "card" => "Test Card",
        "type" => "RichText",
        "content_length" => 1200,
        "headings" => [
          { "level" => 1, "text" => "Introduction", "position" => 0, "format" => "html" },
          { "level" => 2, "text" => "Background", "position" => 150, "format" => "html" },
          { "level" => 2, "text" => "Details", "position" => 800, "format" => "markdown" }
        ]
      }
    end

    it "formats outline with indented heading tree" do
      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/outline")
        .to_return(status: 200, body: outline_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Test Card",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["text"]).to include("Introduction")
      expect(json["text"]).to include("Background")
      expect(json["text"]).to include("Details")
      expect(json["metadata"]["heading_count"]).to eq(3)
      expect(json["metadata"]["content_length"]).to eq(1200)
    end

    it "handles cards with no headings" do
      no_headings_response = {
        "card" => "Plain Card",
        "type" => "RichText",
        "content_length" => 50,
        "headings" => []
      }

      stub_request(:get, "https://test.example.com/api/mcp/cards/Plain%20Card/outline")
        .to_return(status: 200, body: no_headings_response.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        name: "Plain Card",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["text"]).to include("No headings found")
    end
  end

  describe Magi::Archive::Mcp::Server::Tools::SubmitFeedback do
    it "returns success on feedback submission" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/MCP%20Agent%20Feedback%2Blog")
        .to_return(
          status: 200,
          body: { "name" => "MCP Agent Feedback+log", "type" => "RichText", "id" => 99 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      response = described_class.call(
        category: "bug",
        message: "Search returns duplicates",
        tool_name: "search_cards",
        server_context: server_context
      )

      json = JSON.parse(response.content.first[:text])
      expect(json["status"]).to eq("success")
      expect(json["metadata"]["category"]).to eq("bug")
      expect(json["metadata"]["tool_name"]).to eq("search_cards")
    end

    it "handles errors gracefully" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/MCP%20Agent%20Feedback%2Blog")
        .to_return(status: 500, body: { "error" => "server_error" }.to_json, headers: { "Content-Type" => "application/json" })

      # After retries, should get create fallback, which also fails
      stub_request(:post, "https://test.example.com/api/mcp/cards")
        .to_return(status: 500, body: { "error" => "server_error" }.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.call(
        category: "other",
        message: "test",
        server_context: server_context
      )

      expect(response.error?).to be true
    end
  end
end

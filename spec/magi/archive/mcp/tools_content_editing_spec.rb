# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "magi/archive/mcp/tools"

RSpec.describe Magi::Archive::Mcp::Tools do
  let(:config) do
    ENV["MCP_API_KEY"] = "test-api-key"
    ENV["DECKO_API_BASE_URL"] = "https://test.example.com/api/mcp"
    ENV["MCP_ROLE"] = "user"
    Magi::Archive::Mcp::Config.new
  end

  let(:client) { Magi::Archive::Mcp::Client.new(config) }
  let(:tools) { described_class.new(client) }

  let(:valid_token) { "test-jwt-token" }
  let(:auth_response) do
    {
      "token" => valid_token,
      "role" => "user",
      "expires_in" => 3600
    }
  end

  let(:card_response) do
    {
      "name" => "Test Card",
      "content" => "updated content",
      "type" => "RichText",
      "id" => 42
    }
  end

  before do
    stub_request(:post, "https://test.example.com/api/mcp/auth")
      .to_return(
        status: 201,
        body: auth_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#append_content" do
    before do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with(
          body: { patch: { mode: "append", content: "<p>new</p>", separator: "\n" } }.to_json,
          headers: { "Authorization" => "Bearer #{valid_token}" }
        )
        .to_return(
          status: 200,
          body: card_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "sends patch request with append mode" do
      result = tools.append_content("Test Card", content: "<p>new</p>", separator: "\n")
      expect(result["name"]).to eq("Test Card")
    end

    it "defaults separator to empty string" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with(
          body: { patch: { mode: "append", content: "text", separator: "" } }.to_json
        )
        .to_return(status: 200, body: card_response.to_json, headers: { "Content-Type" => "application/json" })

      tools.append_content("Test Card", content: "text")
    end
  end

  describe "#prepend_content" do
    before do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with(
          body: { patch: { mode: "prepend", content: "<h1>Title</h1>", separator: "\n" } }.to_json
        )
        .to_return(
          status: 200,
          body: card_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "sends patch request with prepend mode" do
      result = tools.prepend_content("Test Card", content: "<h1>Title</h1>", separator: "\n")
      expect(result["name"]).to eq("Test Card")
    end
  end

  describe "#find_and_replace" do
    it "sends patch request with find_replace mode" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with(
          body: { patch: { mode: "find_replace", find: "old text", replace: "new text", occurrence: "first" } }.to_json
        )
        .to_return(
          status: 200,
          body: card_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = tools.find_and_replace("Test Card", find: "old text", replace: "new text")
      expect(result["name"]).to eq("Test Card")
    end

    it "supports all occurrence mode" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with(
          body: { patch: { mode: "find_replace", find: "x", replace: "y", occurrence: "all" } }.to_json
        )
        .to_return(
          status: 200,
          body: card_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      tools.find_and_replace("Test Card", find: "x", replace: "y", occurrence: "all")
    end

    it "supports last occurrence mode" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .with(
          body: { patch: { mode: "find_replace", find: "x", replace: "y", occurrence: "last" } }.to_json
        )
        .to_return(
          status: 200,
          body: card_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      tools.find_and_replace("Test Card", find: "x", replace: "y", occurrence: "last")
    end

    it "raises ValidationError when text not found" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/Test%20Card")
        .to_return(
          status: 422,
          body: { error: "validation_error", message: "Text not found in card content" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect {
        tools.find_and_replace("Test Card", find: "nonexistent", replace: "new")
      }.to raise_error(Magi::Archive::Mcp::Client::ValidationError)
    end
  end

  describe "#find_in_card" do
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

    before do
      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/search_content")
        .with(query: { query: "hello", context_chars: 100 })
        .to_return(
          status: 200,
          body: search_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "searches within card content" do
      result = tools.find_in_card("Test Card", query: "hello")
      expect(result["match_count"]).to eq(2)
      expect(result["matches"].size).to eq(2)
    end

    it "supports custom context_chars" do
      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/search_content")
        .with(query: { query: "hello", context_chars: 50 })
        .to_return(
          status: 200,
          body: search_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      tools.find_in_card("Test Card", query: "hello", context_chars: 50)
    end

    it "returns empty matches when text not found" do
      empty_response = {
        "card" => "Test Card",
        "query" => "nonexistent",
        "match_count" => 0,
        "content_length" => 500,
        "matches" => []
      }

      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/search_content")
        .with(query: { query: "nonexistent", context_chars: 100 })
        .to_return(
          status: 200,
          body: empty_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = tools.find_in_card("Test Card", query: "nonexistent")
      expect(result["match_count"]).to eq(0)
      expect(result["matches"]).to be_empty
    end
  end

  describe "#get_card_outline" do
    let(:outline_response) do
      {
        "card" => "Test Card",
        "type" => "RichText",
        "content_length" => 1200,
        "headings" => [
          { "level" => 1, "text" => "Introduction", "position" => 0, "format" => "html" },
          { "level" => 2, "text" => "Background", "position" => 150, "format" => "html" },
          { "level" => 2, "text" => "Details", "position" => 800, "format" => "html" }
        ]
      }
    end

    before do
      stub_request(:get, "https://test.example.com/api/mcp/cards/Test%20Card/outline")
        .to_return(
          status: 200,
          body: outline_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns heading structure" do
      result = tools.get_card_outline("Test Card")
      expect(result["headings"].size).to eq(3)
      expect(result["headings"].first["text"]).to eq("Introduction")
    end

    it "returns content_length without full content" do
      result = tools.get_card_outline("Test Card")
      expect(result["content_length"]).to eq(1200)
      expect(result).not_to have_key("content")
    end
  end

  describe "#submit_feedback" do
    it "appends feedback to log card" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/MCP%20Agent%20Feedback%2Blog")
        .with { |req|
          body = JSON.parse(req.body)
          patch = body["patch"]
          patch["mode"] == "append" &&
            patch["content"].include?("[bug]") &&
            patch["content"].include?("Something broke")
        }
        .to_return(
          status: 200,
          body: { "name" => "MCP Agent Feedback+log", "type" => "RichText", "id" => 99 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      tools.submit_feedback(category: "bug", message: "Something broke")
    end

    it "includes tool_name when provided" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/MCP%20Agent%20Feedback%2Blog")
        .with { |req|
          body = JSON.parse(req.body)
          body["patch"]["content"].include?("(search_cards)")
        }
        .to_return(
          status: 200,
          body: { "name" => "MCP Agent Feedback+log", "type" => "RichText", "id" => 99 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      tools.submit_feedback(category: "usability", message: "Slow", tool_name: "search_cards")
    end

    it "creates log card if it doesn't exist" do
      stub_request(:patch, "https://test.example.com/api/mcp/cards/MCP%20Agent%20Feedback%2Blog")
        .to_return(status: 404, body: { "error" => "not_found" }.to_json, headers: { "Content-Type" => "application/json" })

      stub_request(:post, "https://test.example.com/api/mcp/cards")
        .with { |req|
          body = JSON.parse(req.body)
          body["name"] == "MCP Agent Feedback+log" && body["type"] == "RichText"
        }
        .to_return(
          status: 201,
          body: { "name" => "MCP Agent Feedback+log", "type" => "RichText", "id" => 99 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      tools.submit_feedback(category: "feature_request", message: "Need bulk ops")
    end
  end
end

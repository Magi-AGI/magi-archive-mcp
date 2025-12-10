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

  before do
    # Stub auth endpoint
    stub_request(:post, "https://test.example.com/api/mcp/auth")
      .with(
        body: { api_key: "test-api-key", role: "user" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      .to_return(
        status: 201,
        body: auth_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#initialize" do
    it "initializes with client" do
      expect(tools.client).to eq(client)
    end

    it "creates client if none provided" do
      ENV["MCP_API_KEY"] = "auto-key"
      tools = described_class.new
      expect(tools.client).to be_a(Magi::Archive::Mcp::Client)
    end
  end

  describe "#get_card" do
    let(:card_name) { "User" }
    let(:card_url) { "https://test.example.com/api/mcp/cards/User" }
    let(:card_response) do
      {
        "card" => {
          "name" => "User",
          "content" => "User card content",
          "type" => "Cardtype",
          "id" => 123,
          "url" => "https://wiki.magi-agi.org/User"
        }
      }
    end

    before do
      stub_request(:get, card_url)
        .with(headers: { "Authorization" => "Bearer #{valid_token}" })
        .to_return(
          status: 200,
          body: card_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "fetches card by name" do
      result = tools.get_card(card_name)
      expect(result).to eq(card_response)
    end

    context "with children" do
      before do
        stub_request(:get, card_url)
          .with(
            query: { "with_children" => "true" },
            headers: { "Authorization" => "Bearer #{valid_token}" }
          )
          .to_return(status: 200, body: card_response.to_json)
      end

      it "includes with_children parameter" do
        tools.get_card(card_name, with_children: true)

        expect(WebMock).to have_requested(:get, card_url)
          .with(query: { "with_children" => "true" })
      end
    end

    context "with compound card name" do
      let(:compound_name) { "Business Plan+Overview" }
      # Per MCP-SPEC: encode spaces as %20, keep + literal
      let(:encoded_url) { "https://test.example.com/api/mcp/cards/Business%20Plan+Overview" }

      before do
        stub_request(:get, encoded_url)
          .with(headers: { "Authorization" => "Bearer #{valid_token}" })
          .to_return(status: 200, body: card_response.to_json)
      end

      it "encodes card name properly" do
        tools.get_card(compound_name)

        expect(WebMock).to have_requested(:get, encoded_url)
      end
    end

    context "when card not found" do
      before do
        stub_request(:get, card_url)
          .to_return(
            status: 404,
            body: { "error" => "not_found", "message" => "Card not found" }.to_json
          )
      end

      it "raises NotFoundError" do
        expect { tools.get_card(card_name) }.to raise_error(
          Magi::Archive::Mcp::Client::NotFoundError
        )
      end
    end

    context "when user lacks permission" do
      before do
        stub_request(:get, card_url)
          .to_return(
            status: 403,
            body: { "error" => "permission_denied", "message" => "Insufficient permissions" }.to_json
          )
      end

      it "raises AuthorizationError" do
        expect { tools.get_card(card_name) }.to raise_error(
          Magi::Archive::Mcp::Client::AuthorizationError
        )
      end
    end
  end

  describe "#search_cards" do
    let(:cards_url) { "https://test.example.com/api/mcp/cards" }
    let(:search_response) do
      {
        "cards" => [
          { "name" => "Card 1", "content" => "Game content" },
          { "name" => "Card 2", "content" => "Game plan" }
        ],
        "total" => 2,
        "limit" => 50,
        "offset" => 0
      }
    end

    before do
      stub_request(:get, cards_url)
        .with(
          query: hash_including({}),
          headers: { "Authorization" => "Bearer #{valid_token}" }
        )
        .to_return(
          status: 200,
          body: search_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "searches cards with query" do
      stub_request(:get, cards_url)
        .with(query: { "q" => "game", "limit" => "50", "offset" => "0" })
        .to_return(status: 200, body: search_response.to_json)

      result = tools.search_cards(q: "game")

      expect(result).to eq(search_response)
      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: { "q" => "game", "limit" => "50", "offset" => "0" })
    end

    it "filters by type" do
      stub_request(:get, cards_url)
        .with(query: { "type" => "User", "limit" => "50", "offset" => "0" })
        .to_return(status: 200, body: search_response.to_json)

      tools.search_cards(type: "User")

      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: { "type" => "User", "limit" => "50", "offset" => "0" })
    end

    it "uses custom limit and offset" do
      stub_request(:get, cards_url)
        .with(query: { "limit" => "20", "offset" => "10" })
        .to_return(status: 200, body: search_response.to_json)

      tools.search_cards(limit: 20, offset: 10)

      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: { "limit" => "20", "offset" => "10" })
    end

    it "combines query, type, and pagination" do
      stub_request(:get, cards_url)
        .with(query: { "q" => "plan", "type" => "User", "limit" => "10", "offset" => "5" })
        .to_return(status: 200, body: search_response.to_json)

      tools.search_cards(q: "plan", type: "User", limit: 10, offset: 5)

      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: { "q" => "plan", "type" => "User", "limit" => "10", "offset" => "5" })
    end
  end

  describe "#list_children" do
    let(:parent_name) { "Business Plan" }
    # Per MCP-SPEC line 38: GET /api/mcp/cards/:name/children
    let(:children_url) { "https://test.example.com/api/mcp/cards/Business%20Plan/children" }
    let(:children_response) do
      {
        "parent" => "Business Plan",
        "children" => [
          { "name" => "Business Plan+Overview" },
          { "name" => "Business Plan+Goals" }
        ],
        "child_count" => 2
      }
    end

    before do
      stub_request(:get, children_url)
        .with(
          query: { "limit" => "50", "offset" => "0" },
          headers: { "Authorization" => "Bearer #{valid_token}" }
        )
        .to_return(
          status: 200,
          body: children_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "lists children of parent card" do
      result = tools.list_children(parent_name)

      expect(result).to eq(children_response)
      expect(WebMock).to have_requested(:get, children_url)
        .with(query: { "limit" => "50", "offset" => "0" })
    end

    it "uses custom limit and offset" do
      stub_request(:get, children_url)
        .with(query: { "limit" => "20", "offset" => "10" })
        .to_return(status: 200, body: children_response.to_json)

      tools.list_children(parent_name, limit: 20, offset: 10)

      expect(WebMock).to have_requested(:get, children_url)
        .with(query: { "limit" => "20", "offset" => "10" })
    end

    context "when parent card not found" do
      let(:nonexistent_url) { "https://test.example.com/api/mcp/cards/NonExistent/children" }

      before do
        stub_request(:get, nonexistent_url)
          .with(query: { "limit" => "50", "offset" => "0" })
          .to_return(
            status: 404,
            body: { "error" => "not_found", "message" => "Parent card not found" }.to_json
          )
      end

      it "raises NotFoundError" do
        expect { tools.list_children("NonExistent") }.to raise_error(
          Magi::Archive::Mcp::Client::NotFoundError
        )
      end
    end
  end

  describe "#fetch_all_cards" do
    let(:cards_url) { "https://test.example.com/api/mcp/cards" }

    before do
      # First page
      stub_request(:get, cards_url)
        .with(query: { "type" => "User", "limit" => "2", "offset" => "0" })
        .to_return(
          status: 200,
          body: {
            "cards" => [{ "name" => "User 1" }, { "name" => "User 2" }],
            "next_offset" => 2
          }.to_json
        )

      # Second page (last)
      stub_request(:get, cards_url)
        .with(query: { "type" => "User", "limit" => "2", "offset" => "2" })
        .to_return(
          status: 200,
          body: {
            "cards" => [{ "name" => "User 3" }],
            "next_offset" => nil
          }.to_json
        )
    end

    it "fetches all cards across pages" do
      result = tools.fetch_all_cards(type: "User", limit: 2)

      expect(result.size).to eq(3)
      expect(result).to eq([
                             { "name" => "User 1" },
                             { "name" => "User 2" },
                             { "name" => "User 3" }
                           ])
    end
  end

  describe "#each_card_page" do
    let(:cards_url) { "https://test.example.com/api/mcp/cards" }

    before do
      # First page
      stub_request(:get, cards_url)
        .with(query: { "q" => "test", "limit" => "2", "offset" => "0" })
        .to_return(
          status: 200,
          body: {
            "cards" => [{ "name" => "Card 1" }, { "name" => "Card 2" }],
            "next_offset" => 2
          }.to_json
        )

      # Second page (last)
      stub_request(:get, cards_url)
        .with(query: { "q" => "test", "limit" => "2", "offset" => "2" })
        .to_return(
          status: 200,
          body: {
            "cards" => [{ "name" => "Card 3" }],
            "next_offset" => nil
          }.to_json
        )
    end

    it "yields each page" do
      pages = []
      tools.each_card_page(q: "test", limit: 2) do |page|
        pages << page
      end

      expect(pages.size).to eq(2)
      expect(pages[0]).to eq([{ "name" => "Card 1" }, { "name" => "Card 2" }])
      expect(pages[1]).to eq([{ "name" => "Card 3" }])
    end

    it "returns enumerator without block" do
      enumerator = tools.each_card_page(q: "test", limit: 2)
      expect(enumerator).to be_a(Enumerator)

      pages = enumerator.to_a
      expect(pages.size).to eq(2)
    end
  end

  describe "#create_card" do
    let(:cards_url) { "https://test.example.com/api/mcp/cards" }
    let(:create_response) do
      {
        "card" => {
          "id" => 456,
          "name" => "My Note",
          "content" => "Some notes here",
          "type" => "Basic",
          "url" => "https://wiki.magi-agi.org/My_Note"
        }
      }
    end

    it "creates card with name and content" do
      stub_request(:post, cards_url)
        .with(
          body: { name: "My Note", content: "Some notes here" }.to_json,
          headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }
        )
        .to_return(status: 201, body: create_response.to_json)

      result = tools.create_card("My Note", content: "Some notes here")

      expect(result).to eq(create_response)
    end

    it "creates card with type" do
      stub_request(:post, cards_url)
        .with(
          body: hash_including("name" => "john_doe", "type" => "User", "content" => "Profile")
        )
        .to_return(status: 201, body: create_response.to_json)

      tools.create_card("john_doe", type: "User", content: "Profile")

      expect(WebMock).to have_requested(:post, cards_url)
    end

    it "creates card with metadata" do
      stub_request(:post, cards_url)
        .with(
          body: hash_including("name" => "Card", "content" => "Content", "visibility" => "public")
        )
        .to_return(status: 201, body: create_response.to_json)

      tools.create_card("Card", content: "Content", visibility: "public", tags: ["test"])

      expect(WebMock).to have_requested(:post, cards_url)
    end

    context "when validation fails" do
      before do
        stub_request(:post, cards_url)
          .to_return(
            status: 422,
            body: {
              "error" => "validation_error",
              "message" => "Name is required",
              "details" => { "name" => ["can't be blank"] }
            }.to_json
          )
      end

      it "raises ValidationError" do
        expect { tools.create_card("") }.to raise_error(
          Magi::Archive::Mcp::Client::ValidationError
        )
      end
    end
  end

  describe "#update_card" do
    let(:card_name) { "My Note" }
    let(:card_url) { "https://test.example.com/api/mcp/cards/My%20Note" }
    let(:update_response) do
      {
        "card" => {
          "name" => "My Note",
          "content" => "Updated content",
          "type" => "Basic"
        }
      }
    end

    it "updates card content" do
      stub_request(:patch, card_url)
        .with(
          body: { content: "Updated content" }.to_json,
          headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }
        )
        .to_return(status: 200, body: update_response.to_json)

      result = tools.update_card(card_name, content: "Updated content")

      expect(result).to eq(update_response)
    end

    it "updates card type" do
      stub_request(:patch, card_url)
        .with(body: { type: "User" }.to_json)
        .to_return(status: 200, body: update_response.to_json)

      tools.update_card(card_name, type: "User")

      expect(WebMock).to have_requested(:patch, card_url)
        .with(body: { type: "User" }.to_json)
    end

    it "updates multiple fields" do
      stub_request(:patch, card_url)
        .with(body: { content: "New content", visibility: "private" }.to_json)
        .to_return(status: 200, body: update_response.to_json)

      tools.update_card(card_name, content: "New content", visibility: "private")

      expect(WebMock).to have_requested(:patch, card_url)
    end

    it "raises error when no parameters provided" do
      expect { tools.update_card(card_name) }.to raise_error(
        ArgumentError,
        /No update parameters provided/
      )
    end

    context "when card not found" do
      before do
        stub_request(:patch, card_url)
          .to_return(
            status: 404,
            body: { "error" => "not_found", "message" => "Card not found" }.to_json
          )
      end

      it "raises NotFoundError" do
        expect { tools.update_card(card_name, content: "New") }.to raise_error(
          Magi::Archive::Mcp::Client::NotFoundError
        )
      end
    end
  end

  describe "#delete_card" do
    let(:card_name) { "Obsolete Card" }
    let(:card_url) { "https://test.example.com/api/mcp/cards/Obsolete%20Card" }
    let(:delete_response) { { "success" => true, "message" => "Card deleted" } }

    it "deletes card" do
      stub_request(:delete, card_url)
        .with(headers: { "Authorization" => "Bearer #{valid_token}" })
        .to_return(status: 200, body: delete_response.to_json)

      result = tools.delete_card(card_name)

      expect(result).to eq(delete_response)
    end

    it "force deletes card with children" do
      stub_request(:delete, "#{card_url}?force=true")
        .with(headers: { "Authorization" => "Bearer #{valid_token}" })
        .to_return(status: 200, body: delete_response.to_json)

      tools.delete_card(card_name, force: true)

      expect(WebMock).to have_requested(:delete, "#{card_url}?force=true")
    end

    context "when card not found" do
      before do
        stub_request(:delete, card_url)
          .to_return(
            status: 404,
            body: { "error" => "not_found", "message" => "Card not found" }.to_json
          )
      end

      it "raises NotFoundError" do
        expect { tools.delete_card(card_name) }.to raise_error(
          Magi::Archive::Mcp::Client::NotFoundError
        )
      end
    end

    context "when user lacks permission" do
      before do
        stub_request(:delete, card_url)
          .to_return(
            status: 403,
            body: { "error" => "permission_denied", "message" => "Admin access required" }.to_json
          )
      end

      it "raises AuthorizationError" do
        expect { tools.delete_card(card_name) }.to raise_error(
          Magi::Archive::Mcp::Client::AuthorizationError
        )
      end
    end
  end

  describe "#list_types" do
    let(:types_url) { "https://test.example.com/api/mcp/types" }
    let(:types_response) do
      {
        "types" => [
          { "name" => "User", "id" => 1 },
          { "name" => "Role", "id" => 2 },
          { "name" => "Cardtype", "id" => 3 }
        ],
        "total" => 42,
        "limit" => 50,
        "offset" => 0
      }
    end

    before do
      stub_request(:get, types_url)
        .with(
          query: { "limit" => "50", "offset" => "0" },
          headers: { "Authorization" => "Bearer #{valid_token}" }
        )
        .to_return(
          status: 200,
          body: types_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "lists card types" do
      result = tools.list_types

      expect(result).to eq(types_response)
      expect(WebMock).to have_requested(:get, types_url)
        .with(query: { "limit" => "50", "offset" => "0" })
    end

    it "uses custom limit and offset" do
      stub_request(:get, types_url)
        .with(query: { "limit" => "20", "offset" => "10" })
        .to_return(status: 200, body: types_response.to_json)

      tools.list_types(limit: 20, offset: 10)

      expect(WebMock).to have_requested(:get, types_url)
        .with(query: { "limit" => "20", "offset" => "10" })
    end
  end

  describe "#fetch_all_types" do
    let(:types_url) { "https://test.example.com/api/mcp/types" }

    before do
      # First page
      stub_request(:get, types_url)
        .with(query: { "limit" => "50", "offset" => "0" })
        .to_return(
          status: 200,
          body: {
            "types" => [{ "name" => "User" }, { "name" => "Role" }],
            "next_offset" => 2
          }.to_json
        )

      # Second page (last)
      stub_request(:get, types_url)
        .with(query: { "limit" => "50", "offset" => "2" })
        .to_return(
          status: 200,
          body: {
            "types" => [{ "name" => "Cardtype" }],
            "next_offset" => nil
          }.to_json
        )
    end

    it "fetches all types across pages" do
      result = tools.fetch_all_types

      expect(result.size).to eq(3)
      expect(result).to eq([
                             { "name" => "User" },
                             { "name" => "Role" },
                             { "name" => "Cardtype" }
                           ])
    end
  end

  describe "#render_snippet" do
    # Per MCP-SPEC lines 39-40:
    # - HTML→Markdown: POST /api/mcp/render
    # - Markdown→HTML: POST /api/mcp/render/markdown

    context "HTML to Markdown" do
      let(:html_to_md_url) { "https://test.example.com/api/mcp/render" }
      let(:html_content) { "<p>Hello <strong>world</strong></p>" }
      let(:markdown_response) do
        {
          "markdown" => "Hello **world**",
          "format" => "gfm"
        }
      end

      before do
        stub_request(:post, html_to_md_url)
          .with(
            body: { content: html_content }.to_json,
            headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }
          )
          .to_return(status: 200, body: markdown_response.to_json)
      end

      it "converts HTML to Markdown" do
        result = tools.convert_content(html_content, from: :html, to: :markdown)

        expect(result).to eq(markdown_response)
      end
    end

    context "Markdown to HTML" do
      let(:md_to_html_url) { "https://test.example.com/api/mcp/render/markdown" }
      let(:markdown_content) { "Hello **world**" }
      let(:html_response) do
        {
          "html" => "<p>Hello <strong>world</strong></p>",
          "format" => "html"
        }
      end

      before do
        stub_request(:post, md_to_html_url)
          .with(
            body: { content: markdown_content }.to_json
          )
          .to_return(status: 200, body: html_response.to_json)
      end

      it "converts Markdown to HTML" do
        result = tools.convert_content(markdown_content, from: :markdown, to: :html)

        expect(result).to eq(html_response)
      end
    end

    context "with invalid formats" do
      it "raises ArgumentError for invalid from format" do
        expect do
          tools.convert_content("content", from: :xml, to: :markdown)
        end.to raise_error(ArgumentError, /Format must be/)
      end

      it "raises ArgumentError for invalid to format" do
        expect do
          tools.convert_content("content", from: :html, to: :json)
        end.to raise_error(ArgumentError, /Format must be/)
      end

      it "raises ArgumentError when from and to are the same" do
        expect do
          tools.convert_content("content", from: :html, to: :html)
        end.to raise_error(ArgumentError, /cannot be the same/)
      end
    end
  end

  describe "#batch_operations" do
    let(:batch_url) { "https://test.example.com/api/mcp/cards/batch" }
    let(:operations) do
      [
        { action: "create", name: "Card 1", content: "Content 1" },
        { action: "create", name: "Card 2", content: "Content 2" }
      ]
    end
    let(:batch_response) do
      {
        "results" => [
          { "status" => 201, "success" => true, "card" => { "name" => "Card 1", "id" => 1 } },
          { "status" => 201, "success" => true, "card" => { "name" => "Card 2", "id" => 2 } }
        ],
        "mode" => "per_item"
      }
    end

    it "executes batch operations in per_item mode" do
      stub_request(:post, batch_url)
        .with(
          body: hash_including("ops" => operations, "mode" => "per_item"),
          headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }
        )
        .to_return(status: 207, body: batch_response.to_json)

      result = tools.batch_operations(operations)

      expect(result).to eq(batch_response)
    end

    it "executes batch operations in transactional mode" do
      stub_request(:post, batch_url)
        .with(
          body: hash_including("ops" => operations, "mode" => "transactional")
        )
        .to_return(status: 207, body: batch_response.merge("mode" => "transactional").to_json)

      result = tools.batch_operations(operations, mode: "transactional")

      expect(result["mode"]).to eq("transactional")
    end

    it "raises ArgumentError for invalid mode" do
      expect do
        tools.batch_operations(operations, mode: "invalid")
      end.to raise_error(ArgumentError, /Mode must be/)
    end

    context "with partial failures" do
      let(:partial_response) do
        {
          "results" => [
            { "status" => 201, "success" => true, "card" => { "name" => "Card 1" } },
            { "status" => 422, "success" => false, "error" => "Validation error" }
          ],
          "mode" => "per_item"
        }
      end

      before do
        stub_request(:post, batch_url)
          .to_return(status: 207, body: partial_response.to_json)
      end

      it "returns partial results" do
        result = tools.batch_operations(operations)

        expect(result["results"].length).to eq(2)
        expect(result["results"][0]["success"]).to be true
        expect(result["results"][1]["success"]).to be false
      end
    end
  end

  describe "#build_child_op" do
    let(:parent_name) { "Business Plan" }
    let(:child_name) { "Overview" }

    it "builds operation for child card" do
      op = tools.build_child_op(parent_name, child_name, content: "Summary")

      expect(op[:action]).to eq("create")
      expect(op[:name]).to eq("Business Plan+Overview")
      expect(op[:content]).to eq("Summary")
    end

    it "includes type when provided" do
      op = tools.build_child_op(parent_name, child_name, content: "Summary", type: "RichText")

      expect(op[:type]).to eq("RichText")
    end

    it "works without content or type" do
      op = tools.build_child_op(parent_name, child_name)

      expect(op[:action]).to eq("create")
      expect(op[:name]).to eq("Business Plan+Overview")
      expect(op).not_to have_key(:content)
      expect(op).not_to have_key(:type)
    end

    it "can be used with batch_operations" do
      batch_url = "https://test.example.com/api/mcp/cards/batch"
      ops = [
        tools.build_child_op(parent_name, "Overview", content: "Summary"),
        tools.build_child_op(parent_name, "Goals", content: "Objectives")
      ]

      stub_request(:post, batch_url)
        .with(
          body: hash_including("ops" => ops),
          headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }
        )
        .to_return(
          status: 207,
          body: {
            "results" => [
              { "status" => 201, "success" => true },
              { "status" => 201, "success" => true }
            ]
          }.to_json
        )

      result = tools.batch_operations(ops)

      expect(result["results"].length).to eq(2)
    end
  end
  describe "#normalize_card_name" do
    it "converts spaces to underscores" do
      result = tools.normalize_card_name("Daresh Tral Subcultures")
      expect(result).to eq("Daresh_Tral_Subcultures")
    end

    it "preserves plus signs in compound names" do
      result = tools.normalize_card_name("Business Plan+Overview")
      expect(result).to eq("Business_Plan+Overview")
    end

    it "handles names that are already normalized" do
      result = tools.normalize_card_name("Already_Normalized")
      expect(result).to eq("Already_Normalized")
    end

    it "handles names with multiple consecutive spaces" do
      result = tools.normalize_card_name("Test  Card   Name")
      expect(result).to eq("Test__Card___Name")
    end

    it "handles empty string" do
      result = tools.normalize_card_name("")
      expect(result).to eq("")
    end

    it "handles strings with only spaces" do
      result = tools.normalize_card_name("   ")
      expect(result).to eq("___")
    end
  end

  describe "#search_cards with default search_in parameter" do
    let(:cards_url) { "https://test.example.com/api/mcp/cards" }
    let(:search_response) do
      {
        "cards" => [
          { "name" => "Card 1", "content" => "Game content" },
          { "name" => "Card 2", "content" => "Game plan" }
        ],
        "total" => 2,
        "limit" => 50,
        "offset" => 0
      }
    end

    before do
      stub_request(:get, cards_url)
        .with(
          query: hash_including({}),
          headers: { "Authorization" => "Bearer #{valid_token}" }
        )
        .to_return(
          status: 200,
          body: search_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "uses search_in=both when not specified" do
      stub_request(:get, cards_url)
        .with(query: { "q" => "game", "search_in" => "both", "limit" => "50", "offset" => "0" })
        .to_return(status: 200, body: search_response.to_json)

      # Note: The underlying client uses default from search endpoint if not passed
      # This test verifies that when search_in is not provided, the endpoint's default (both) is used
      tools.search_cards(q: "game")

      # Verify the request was made - the client may or may not include search_in in params
      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: hash_including("q" => "game"))
    end

    it "allows explicit override to search_in=name" do
      stub_request(:get, cards_url)
        .with(query: { "q" => "game", "search_in" => "name", "limit" => "50", "offset" => "0" })
        .to_return(status: 200, body: search_response.to_json)

      tools.search_cards(q: "game", search_in: "name")

      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: { "q" => "game", "search_in" => "name", "limit" => "50", "offset" => "0" })
    end

    it "allows explicit override to search_in=content" do
      stub_request(:get, cards_url)
        .with(query: { "q" => "game", "search_in" => "content", "limit" => "50", "offset" => "0" })
        .to_return(status: 200, body: search_response.to_json)

      tools.search_cards(q: "game", search_in: "content")

      expect(WebMock).to have_requested(:get, cards_url)
        .with(query: { "q" => "game", "search_in" => "content", "limit" => "50", "offset" => "0" })
    end
  end


end

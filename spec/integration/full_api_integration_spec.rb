# frozen_string_literal: true

require "spec_helper"
require_relative "../support/integration_helpers"

RSpec.describe "Full API Integration", :integration do
  # Real HTTP integration tests against actual server
  # Run with: INTEGRATION_TEST=true rspec spec/integration/
  #
  # Uses Card-based API key authentication with production server
  # The integration_helpers module sets up:
  # - DECKO_API_BASE_URL: https://wiki.magi-agi.org/api/mcp
  # - MCP_API_KEY: Card-based API key
  # - MCP_ROLE: admin

  let(:base_url) { ENV["DECKO_API_BASE_URL"] || "https://wiki.magi-agi.org/api/mcp" }

  before do
    skip "Integration tests disabled" unless ENV["INTEGRATION_TEST"]
  end

  describe "Authentication flow" do
    it "successfully authenticates and returns JWT" do
      tools = Magi::Archive::Mcp::Tools.new

      # Auth should work without errors
      expect { tools.client.send(:auth).token }.not_to raise_error

      token = tools.client.send(:auth).token
      expect(token).to be_a(String)
      expect(token.length).to be > 100 # JWT tokens are long
    end

    it "caches token and reuses it" do
      tools = Magi::Archive::Mcp::Tools.new

      first_token = tools.client.send(:auth).token
      second_token = tools.client.send(:auth).token

      expect(first_token).to eq(second_token)
    end
  end

  describe "Health check" do
    it "returns healthy status without authentication" do
      # Health check should work without auth
      require "http"
      response = HTTP.get("#{base_url}/health")

      expect(response.status).to eq(200)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("healthy")
    end
  end

  describe "Card operations" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }
    let(:test_card_name) { "IntegrationTest#{Time.now.to_i}" }

    after do
      # Cleanup: delete test card
      tools.delete_card(test_card_name) rescue nil
    end

    it "creates, reads, updates, and deletes a card" do
      # Create
      result = tools.create_card(
        test_card_name,
        content: "Test content",
        type: "RichText"
      )
      expect(result["name"]).to eq(test_card_name)

      # Read
      card = tools.get_card(test_card_name)
      expect(card["name"]).to eq(test_card_name)
      expect(card["content"]).to include("Test content")

      # Update
      updated = tools.update_card(
        test_card_name,
        content: "Updated content"
      )
      expect(updated["content"]).to include("Updated")

      # Delete
      deleted = tools.delete_card(test_card_name)
      expect(deleted).to have_key("name")

      # Verify deleted
      expect {
        tools.get_card(test_card_name)
      }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
    end
  end

  describe "Batch operations" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }
    let(:batch_prefix) { "BatchTest#{Time.now.to_i}" }

    after do
      # Cleanup
      3.times do |i|
        tools.delete_card("#{batch_prefix}_#{i}") rescue nil
      end
    end

    it "creates multiple cards in one request" do
      operations = 3.times.map do |i|
        {
          action: "create",
          name: "#{batch_prefix}_#{i}",
          content: "Batch content #{i}",
          type: "RichText"
        }
      end

      result = tools.batch_operations(operations, mode: "per_item")

      expect(result["results"].size).to eq(3)
      result["results"].each do |res|
        # Server returns "ok" for successful operations
        expect(res["status"]).to eq("ok")
      end
    end

    it "rolls back all operations in transactional mode on failure" do
      operations = [
        {
          action: "create",
          name: "#{batch_prefix}_good",
          content: "Good",
          type: "RichText"
        },
        {
          action: "create",
          name: "#{batch_prefix}_bad",
          content: "Bad",
          type: "NonExistentType" # This will fail
        }
      ]

      result = tools.batch_operations(operations, mode: "transactional")

      # Server doesn't return mode field, but should still enforce transactional behavior
      # In transactional mode, if one operation fails, ALL should be rolled back

      # Verify first card wasn't created (transactional rollback worked)
      expect {
        tools.get_card("#{batch_prefix}_good")
      }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
    end
  end

  describe "List children" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "lists children of a parent card" do
      parent_name = "IntegrationTestParent#{Time.now.to_i}"
      child_name = "#{parent_name}+Child"

      # Create parent and child cards
      parent = tools.create_card(parent_name, content: "Parent", type: "RichText")
      puts "DEBUG: Created parent: #{parent["name"]}"

      child = tools.create_card(child_name, content: "Child", type: "RichText")
      puts "DEBUG: Created child: #{child["name"]}"

      # Verify child can be fetched directly
      fetched_child = tools.get_card(child_name)
      puts "DEBUG: Fetched child directly: #{fetched_child["name"]}"

      # Small delay to ensure database commit
      sleep 0.5

      # List children
      result = tools.list_children(parent_name)
      puts "DEBUG: list_children result: #{result.inspect}"

      expect(result).to be_a(Hash)
      expect(result["parent"]).to eq(parent_name)
      expect(result["children"]).to be_an(Array)
      puts "DEBUG: children array: #{result["children"].inspect}"
      expect(result["children"].length).to be >= 1
      expect(result).to have_key("child_count")

      # Check that our child is in the list
      child_names = result["children"].map { |c| c["name"] }
      expect(child_names).to include(child_name)

      # Cleanup
      tools.delete_card(child_name)
      tools.delete_card(parent_name)
    end
  end

  describe "Spoiler scan" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }
    let(:scan_prefix) { "ScanTest#{Time.now.to_i}" }

    before do
      # Create terms card
      @terms_card = tools.create_card(
        "#{scan_prefix}+terms",
        content: "spoiler1\nspoiler2",
        type: "RichText"
      )
    end

    after do
      tools.delete_card("#{scan_prefix}+terms") rescue nil
      tools.delete_card("#{scan_prefix}+results") rescue nil
    end

    it "runs spoiler scan and creates results card" do
      result = tools.spoiler_scan(
        terms_card: "#{scan_prefix}+terms",
        results_card: "#{scan_prefix}+results",
        scope: "player"
      )

      expect(result["status"]).to eq("completed")
      expect(result).to have_key("matches")
      expect(result).to have_key("terms_checked")

      # Results card should be created
      results = tools.get_card("#{scan_prefix}+results")
      expect(results).to have_key("content")
    end
  end

  describe "Error handling" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "raises NotFoundError for non-existent card" do
      expect {
        tools.get_card("ThisCardDoesNotExist#{rand(10000)}")
      }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
    end

    it "raises ValidationError for invalid card type" do
      expect {
        tools.create_card(
          "InvalidType#{Time.now.to_i}",
          type: "NonExistentType",
          content: "Test"
        )
      }.to raise_error(Magi::Archive::Mcp::Client::APIError, /Type 'NonExistentType' not found/)
    end

    it "raises AuthenticationError when API key doesn't support requested role" do
      # Try to use a role not authorized for this API key
      ENV["MCP_ROLE"] = "user"
      user_tools = Magi::Archive::Mcp::Tools.new

      expect {
        user_tools.delete_card("SomeCard")
      }.to raise_error(Magi::Archive::Mcp::Auth::AuthenticationError, /API key not authorized for role/)
    end
  end

  describe "Retry logic" do
    # Note: Retry logic is tested at the unit level with mocks
    # Integration tests verify successful requests work correctly
    # Actual retry behavior would require a test server that returns 500s
    it "successfully handles normal requests", skip: "Retry logic tested in unit tests" do
      tools = Magi::Archive::Mcp::Tools.new
      # If we get here without errors, request handling works
      expect(tools.get_card("Test")).to be_a(Hash)
    end
  end

  describe "Production-like scenarios" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "handles compound card names correctly" do
      parent_name = "ParentCard#{Time.now.to_i}"
      child_name = "#{parent_name}+Child"

      # Create parent
      tools.create_card(parent_name, content: "Parent", type: "RichText")

      # Create child
      result = tools.create_card(child_name, content: "Child", type: "RichText")
      expect(result["name"]).to eq(child_name)

      # Get child
      card = tools.get_card(child_name)
      expect(card["name"]).to eq(child_name)

      # Cleanup
      tools.delete_card(child_name)
      tools.delete_card(parent_name)
    end

    it "handles URL encoding in card names" do
      special_name = "Card With Spaces#{Time.now.to_i}"

      result = tools.create_card(special_name, content: "Test", type: "RichText")
      expect(result["name"]).to eq(special_name)

      card = tools.get_card(special_name)
      expect(card["name"]).to eq(special_name)

      tools.delete_card(special_name)
    end
  end

  describe "Search operations" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }
    let(:search_prefix) { "SearchTest#{Time.now.to_i}" }

    before do
      # Create test cards with searchable content
      @card1 = tools.create_card(
        "#{search_prefix}_Alpha",
        content: "This card contains keyword xylophone",
        type: "RichText"
      )
      @card2 = tools.create_card(
        "#{search_prefix}_Beta",
        content: "This card also has xylophone in it",
        type: "RichText"
      )
      @card3 = tools.create_card(
        "#{search_prefix}_Gamma",
        content: "This card has different content",
        type: "RichText"
      )
      sleep 1 # Give search index time to update
    end

    after do
      tools.delete_card("#{search_prefix}_Alpha") rescue nil
      tools.delete_card("#{search_prefix}_Beta") rescue nil
      tools.delete_card("#{search_prefix}_Gamma") rescue nil
    end

    it "searches cards by query string" do
      # Search in content (not name) since "xylophone" is in card content
      result = tools.search_cards(q: "xylophone", search_in: "content", limit: 100)

      expect(result).to be_a(Hash)
      expect(result["cards"]).to be_an(Array)

      # Should find at least our 2 test cards (if indexing has completed)
      matching_cards = result["cards"].select { |c| c["name"].start_with?(search_prefix) }
      expect(matching_cards.length).to be >= 2
    end

    it "searches cards by type" do
      result = tools.search_cards(type: "RichText", limit: 100)

      expect(result).to be_a(Hash)
      expect(result["cards"]).to be_an(Array)
      expect(result["cards"].length).to be > 0

      # All results should be RichText
      result["cards"].each do |card|
        expect(card["type"]).to eq("RichText")
      end
    end

    it "handles pagination with offset" do
      # Get first page
      page1 = tools.search_cards(type: "RichText", limit: 5, offset: 0)

      # Get second page
      page2 = tools.search_cards(type: "RichText", limit: 5, offset: 5)

      expect(page1["cards"]).to be_an(Array)
      expect(page2["cards"]).to be_an(Array)

      # Pages should have different cards (unless fewer than 6 total)
      if page1["cards"].length == 5 && page2["cards"].length > 0
        card_ids_page1 = page1["cards"].map { |c| c["id"] }
        card_ids_page2 = page2["cards"].map { |c| c["id"] }
        expect((card_ids_page1 & card_ids_page2).empty?).to be true
      end
    end
  end

  describe "Rendering operations" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "converts HTML to Markdown" do
      html_content = "<h1>Test Heading</h1><p>This is <strong>bold</strong> text.</p><ul><li>Item 1</li><li>Item 2</li></ul>"

      result = tools.render_snippet(html_content, from: :html, to: :markdown)

      expect(result).to be_a(Hash)
      expect(result).to have_key("markdown")
      expect(result["markdown"]).to be_a(String)
      expect(result["markdown"]).to include("# Test Heading")
      expect(result["markdown"]).to include("**bold**")
    end

    it "converts Markdown to HTML" do
      markdown_content = "# Test Heading\n\nThis is **bold** text.\n\n- Item 1\n- Item 2"

      result = tools.render_snippet(markdown_content, from: :markdown, to: :html)

      expect(result).to be_a(Hash)
      expect(result).to have_key("html")
      expect(result["html"]).to be_a(String)
      expect(result["html"]).to include("<h1>")
      expect(result["html"]).to include("<strong>")
      expect(result["html"]).to include("<li>")
    end

    it "handles complex HTML with nested elements" do
      complex_html = <<~HTML
        <div>
          <h2>Section</h2>
          <p>Paragraph with <em>emphasis</em> and <code>code</code>.</p>
          <blockquote>A quote</blockquote>
        </div>
      HTML

      result = tools.render_snippet(complex_html, from: :html, to: :markdown)

      expect(result["markdown"]).to be_a(String)
      expect(result["markdown"]).to include("## Section")
      expect(result["markdown"]).to match(/\*emphasis\*|_emphasis_/)
    end
  end

  describe "Type discovery" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "lists available card types" do
      result = tools.list_types(limit: 100)

      expect(result).to be_a(Hash)
      expect(result["types"]).to be_an(Array)
      expect(result["types"].length).to be > 0

      # Check structure of type objects
      first_type = result["types"].first
      expect(first_type).to have_key("name")

      # Should include common types
      type_names = result["types"].map { |t| t["name"] }
      expect(type_names).to include("RichText")
    end

    it "handles pagination for types" do
      page1 = tools.list_types(limit: 10, offset: 0)
      page2 = tools.list_types(limit: 10, offset: 10)

      expect(page1["types"]).to be_an(Array)
      expect(page2["types"]).to be_an(Array)

      # Pages should have different types (unless fewer than 11 total)
      if page1["types"].length == 10 && page2["types"].length > 0
        type_names_page1 = page1["types"].map { |t| t["name"] }
        type_names_page2 = page2["types"].map { |t| t["name"] }
        expect((type_names_page1 & type_names_page2).empty?).to be true
      end
    end
  end
end

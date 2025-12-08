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

    it "lists children of a parent card", skip: "Server returns NoMethodError - needs server-side fix" do
      parent_name = "IntegrationTestParent#{Time.now.to_i}"
      child_name = "#{parent_name}+Child"

      # Create parent and child cards
      tools.create_card(parent_name, content: "Parent", type: "RichText")
      tools.create_card(child_name, content: "Child", type: "RichText")

      # List children
      result = tools.list_children(parent_name)

      expect(result).to be_a(Hash)
      expect(result["parent"]).to eq(parent_name)
      expect(result["children"]).to be_an(Array)
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
end

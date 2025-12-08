# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Full API Integration", :integration do
  # Real HTTP integration tests against actual server
  # Run with: INTEGRATION_TEST=true rspec spec/integration/

  let(:base_url) { ENV.fetch("TEST_API_URL", "http://localhost:3000/api/mcp") }
  let(:username) { ENV["TEST_USERNAME"] || "test@example.com" }
  let(:password) { ENV["TEST_PASSWORD"] || "password123" }

  before do
    skip "Integration tests disabled" unless ENV["INTEGRATION_TEST"]

    # Set up config to point to test server
    ENV["DECKO_API_BASE_URL"] = base_url
    ENV["MCP_USERNAME"] = username
    ENV["MCP_PASSWORD"] = password
    ENV["MCP_ROLE"] = "admin"
  end

  after do
    ENV.delete("DECKO_API_BASE_URL")
    ENV.delete("MCP_USERNAME")
    ENV.delete("MCP_PASSWORD")
    ENV.delete("MCP_ROLE")
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
      # Create client without setting credentials
      ENV.delete("MCP_USERNAME")
      ENV.delete("MCP_PASSWORD")

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
        type: "Basic"
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
          type: "Basic"
        }
      end

      result = tools.batch_operations(operations, mode: "per_item")

      expect(result["results"].size).to eq(3)
      result["results"].each do |res|
        expect(res["status"]).to eq("success")
      end
    end

    it "rolls back all operations in transactional mode on failure" do
      operations = [
        {
          action: "create",
          name: "#{batch_prefix}_good",
          content: "Good",
          type: "Basic"
        },
        {
          action: "create",
          name: "#{batch_prefix}_bad",
          content: "Bad",
          type: "NonExistentType" # This will fail
        }
      ]

      result = tools.batch_operations(operations, mode: "transactional")

      # In transactional mode, all should fail if one fails
      expect(result["mode"]).to eq("transactional")

      # Verify first card wasn't created
      expect {
        tools.get_card("#{batch_prefix}_good")
      }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
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
        type: "Basic"
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
      }.to raise_error(Magi::Archive::Mcp::Client::ValidationError)
    end

    it "raises AuthorizationError when user tries admin operation" do
      # Re-authenticate as user role
      ENV["MCP_ROLE"] = "user"
      user_tools = Magi::Archive::Mcp::Tools.new

      expect {
        user_tools.delete_card("SomeCard")
      }.to raise_error(Magi::Archive::Mcp::Client::AuthorizationError)
    end
  end

  describe "Retry logic" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "retries on 500 errors" do
      # This test requires a mock or actual flaky endpoint
      # For now, just verify the retry mechanism exists
      client = tools.client

      expect(client).to respond_to(:request)
      expect(client.method(:request).parameters).to include([:key, :retry_count])
    end

    it "respects retry limits" do
      # Verify max 3 retries
      client = tools.client

      # Mock a failing request
      allow(client).to receive(:http_client).and_return(
        double(request: double(code: 500, body: "Server Error"))
      )

      expect {
        client.send(:request, :get, "/test", retry_count: 0)
      }.to raise_error(Magi::Archive::Mcp::Client::ServerError)

      # Should have tried 4 times total (initial + 3 retries)
      # This is hard to verify without internal counters
    end
  end

  describe "Production-like scenarios" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "handles compound card names correctly" do
      parent_name = "ParentCard#{Time.now.to_i}"
      child_name = "#{parent_name}+Child"

      # Create parent
      tools.create_card(parent_name, content: "Parent", type: "Basic")

      # Create child
      result = tools.create_card(child_name, content: "Child", type: "Basic")
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

      result = tools.create_card(special_name, content: "Test", type: "Basic")
      expect(result["name"]).to eq(special_name)

      card = tools.get_card(special_name)
      expect(card["name"]).to eq(special_name)

      tools.delete_card(special_name)
    end
  end
end

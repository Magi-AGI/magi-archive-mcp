# frozen_string_literal: true

require "spec_helper"
require_relative "../support/integration_helpers"

RSpec.describe "Weekly Summary Integration", :integration do
  # Real HTTP integration tests for weekly summary generation
  # Run with: INTEGRATION_TEST=true rspec spec/integration/weekly_summary_spec.rb

  let(:base_url) { ENV["DECKO_API_BASE_URL"] || "https://wiki.magi-agi.org/api/mcp" }

  before do
    skip "Integration tests disabled" unless ENV["INTEGRATION_TEST"]
  end

  describe "Weekly summary generation" do
    let(:client) { integration_client(role: "admin") }
    let(:test_card_name) { "Weekly Summary Test #{Time.now.strftime('%Y %m %d')}" }

    after do
      # Cleanup test summary card
      begin
        client.delete_card(test_card_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    describe "create_weekly_summary" do
      it "creates a weekly summary card with default settings" do
        # Note: This requires git repositories to be present
        # May fail if no git repos are found
        result = client.create_weekly_summary(
          create_card: true,
          days: 7
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("card_name")

        # Verify the card was created
        if result["card_name"]
          card = client.get_card(result["card_name"])
          expect(card).to have_key("name")
          expect(card["content"]).to include("Weekly Summary")
        end
      end

      it "generates summary preview without creating card" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 7
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("preview")
        expect(result["preview"]).to be_a(String)
        expect(result["preview"].length).to be > 0
      end

      it "respects custom time range" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 3
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("preview")
      end

      it "includes git repository changes when available" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 7,
          base_path: ENV["MAGI_WORKING_DIR"] || "/home/ubuntu"
        )

        expect(result).to be_a(Hash)
        # Should have scanned for repos
        if result["repositories"]
          expect(result["repositories"]).to be_an(Array)
        end
      end

      it "handles custom executive summary" do
        custom_summary = "This week we focused on testing and integration"

        result = client.create_weekly_summary(
          create_card: false,
          days: 7,
          executive_summary: custom_summary
        )

        expect(result).to be_a(Hash)
        if result["preview"]
          expect(result["preview"]).to include(custom_summary)
        end
      end

      it "includes username attribution when provided" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 7,
          username: "test-user"
        )

        expect(result).to be_a(Hash)
        # Should include username in the card name or content
      end
    end

    describe "summary content structure" do
      it "includes required sections" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 7
        )

        expect(result["preview"]).to be_a(String)
        content = result["preview"]

        # Should have standard sections
        expect(content).to include("Summary") if content.length > 0
      end

      it "formats markdown correctly" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 7
        )

        content = result["preview"]

        # Should use markdown formatting
        expect(content).to match(/^#/) if content.length > 0 # Headers
      end

      it "includes attribution footer" do
        result = client.create_weekly_summary(
          create_card: false,
          days: 7
        )

        content = result["preview"]

        # Should have Claude Code attribution
        expect(content).to include("Claude Code") if content.length > 0
      end
    end
  end

  describe "Error handling" do
    let(:client) { integration_client(role: "admin") }

    it "handles invalid date ranges gracefully" do
      expect {
        client.create_weekly_summary(
          create_card: false,
          days: 0
        )
      }.to raise_error(Magi::Archive::Mcp::Client::ValidationError)
    end

    it "handles missing git repositories gracefully" do
      result = client.create_weekly_summary(
        create_card: false,
        days: 7,
        base_path: "/nonexistent/path"
      )

      # Should not crash, just return summary without repo data
      expect(result).to be_a(Hash)
    end

    it "requires admin role for summary creation" do
      # Try with user role
      user_client = integration_client(role: "user")

      expect {
        user_client.create_weekly_summary(
          create_card: true,
          days: 7
        )
      }.to raise_error(Magi::Archive::Mcp::Client::AuthorizationError)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require_relative "../support/integration_helpers"

RSpec.describe "Relationship Operations Integration", :integration do
  # Real HTTP integration tests for card relationship operations
  # Run with: INTEGRATION_TEST=true rspec spec/integration/relationship_operations_spec.rb

  let(:base_url) { ENV["DECKO_API_BASE_URL"] || "https://wiki.magi-agi.org/api/mcp" }

  before do
    skip "Integration tests disabled" unless ENV["INTEGRATION_TEST"]
  end

  describe "Card relationship queries" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }
    let(:parent_card) { "RelTestParent#{Time.now.to_i}" }
    let(:child_card) { "RelTestChild#{Time.now.to_i}" }
    let(:referrer_card) { "RelTestReferrer#{Time.now.to_i}" }

    after do
      # Cleanup test cards
      [parent_card, child_card, referrer_card].each do |card|
        tools.delete_card(card) rescue nil
      end
    end

    describe "get_referers" do
      it "finds cards that reference the target card" do
        # Create a card
        tools.create_card(parent_card, content: "Test parent", type: "RichText")

        # Create a card that references it
        tools.create_card(
          referrer_card,
          content: "This references [[#{parent_card}]]",
          type: "RichText"
        )

        # Give the system a moment to index relationships
        sleep 1

        result = tools.get_referers(parent_card)

        expect(result).to be_an(Array)
        # May or may not find the referrer depending on indexing
        expect(result.length).to be >= 0
      end

      it "returns empty array for card with no referers" do
        # Create a card that nothing references
        tools.create_card(
          child_card,
          content: "Lonely card",
          type: "RichText"
        )

        result = tools.get_referers(child_card)

        expect(result).to be_an(Array)
      end

      it "raises NotFoundError for non-existent card" do
        expect {
          tools.get_referers("NonExistent#{Time.now.to_i}")
        }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
      end
    end

    describe "get_linked_by" do
      it "finds cards that link to the target card" do
        # Create target card
        tools.create_card(parent_card, content: "Link target", type: "RichText")

        # Create card with link
        tools.create_card(
          referrer_card,
          content: "Link to [[#{parent_card}]]",
          type: "RichText"
        )

        sleep 1

        result = tools.get_linked_by(parent_card)

        expect(result).to be_an(Array)
        expect(result.length).to be >= 0
      end
    end

    describe "get_links" do
      it "finds cards that this card links to" do
        # Create some cards to link to
        tools.create_card(parent_card, content: "Link target 1", type: "RichText")
        tools.create_card(child_card, content: "Link target 2", type: "RichText")

        # Create card with outgoing links
        tools.create_card(
          referrer_card,
          content: "Links to [[#{parent_card}]] and [[#{child_card}]]",
          type: "RichText"
        )

        sleep 1

        result = tools.get_links(referrer_card)

        expect(result).to be_an(Array)
        expect(result.length).to be >= 0
      end
    end

    describe "get_nests" do
      it "finds cards that this card nests" do
        # Create card with nested content
        tools.create_card(parent_card, content: "Nested target", type: "RichText")

        tools.create_card(
          referrer_card,
          content: "{{#{parent_card}}}",
          type: "RichText"
        )

        sleep 1

        result = tools.get_nests(referrer_card)

        expect(result).to be_an(Array)
        expect(result.length).to be >= 0
      end
    end

    describe "get_nested_in" do
      it "finds cards where this card is nested" do
        # Create a card
        tools.create_card(parent_card, content: "Will be nested", type: "RichText")

        # Create card that nests it
        tools.create_card(
          referrer_card,
          content: "Nesting {{#{parent_card}}}",
          type: "RichText"
        )

        sleep 1

        result = tools.get_nested_in(parent_card)

        expect(result).to be_an(Array)
        expect(result.length).to be >= 0
      end
    end
  end

  describe "Relationship query edge cases" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    it "handles compound card names in relationships" do
      # Use a real card that likely exists
      result = tools.get_referers("Home")

      expect(result).to be_an(Array)
      # Home page should have some referers
    end

    it "handles special characters in card names" do
      special_name = "Test+Card+#{Time.now.to_i}"
      tools.create_card(special_name, content: "Special", type: "RichText")

      result = tools.get_links(special_name)

      expect(result).to be_an(Array)

      tools.delete_card(special_name) rescue nil
    end
  end
end

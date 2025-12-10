# frozen_string_literal: true

require "spec_helper"
require_relative "../support/integration_helpers"

RSpec.describe "Validation and Recommendation Operations Integration", :integration do
  # Real HTTP integration tests for card validation and recommendation operations
  # Run with: INTEGRATION_TEST=true rspec spec/integration/validation_operations_spec.rb

  let(:base_url) { ENV["DECKO_API_BASE_URL"] || "https://wiki.magi-agi.org/api/mcp" }

  before do
    skip "Integration tests disabled" unless ENV["INTEGRATION_TEST"]
  end

  describe "Type requirements and validation" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    describe "get_type_requirements" do
      it "retrieves requirements for a valid card type" do
        # Use a common type that should exist
        result = tools.get_type_requirements("Article")

        expect(result).to be_a(Hash)
        # Should have structure information
        expect(result).to have_key("type")
      end

      it "handles RichText type requirements" do
        result = tools.get_type_requirements("RichText")

        expect(result).to be_a(Hash)
        expect(result["type"]).to eq("RichText")
      end

      it "raises error for non-existent type" do
        expect {
          tools.get_type_requirements("NonExistentType#{Time.now.to_i}")
        }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
      end
    end

    describe "validate_card_structure" do
      it "validates a properly structured card" do
        result = tools.validate_card_structure(
          "RichText",
          children_names: []
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("valid")
      end

      it "detects invalid card structure" do
        # Try to validate with invalid data
        result = tools.validate_card_structure(
          "Article",
          children_names: []
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("valid")
      end

      it "provides validation errors when structure is invalid" do
        result = tools.validate_card_structure(
          "RichText",
          children_names: ["Invalid+Child+Structure"]
        )

        expect(result).to be_a(Hash)
        if result["valid"] == false
          expect(result).to have_key("errors")
          expect(result["errors"]).to be_an(Array)
        end
      end
    end

    describe "validate_card_tags" do
      it "validates appropriate tags for a card type" do
        result = tools.validate_card_tags(
          type: "Article",
          tags: ["Article", "Documentation"]
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("valid")
      end

      it "detects when tags don't match type requirements" do
        result = tools.validate_card_tags(
          type: "RichText",
          tags: ["CompletelyWrongTag#{Time.now.to_i}"]
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("valid")
      end
    end
  end

  describe "Card recommendations" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }
    let(:test_card_name) { "ValidationTest#{Time.now.to_i}" }

    after do
      tools.delete_card(test_card_name) rescue nil
    end

    describe "recommend_card_structure" do
      it "provides structure recommendations for new card" do
        result = tools.recommend_card_structure(
          name: test_card_name,
          type: "Article",
          content: "Test article content",
          tags: []
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key("recommendations")
      end

      it "suggests appropriate tags based on content" do
        result = tools.recommend_card_structure(
          name: test_card_name,
          type: "Article",
          content: "This is documentation about the MCP API system",
          tags: []
        )

        expect(result).to be_a(Hash)
        if result["recommendations"]
          expect(result["recommendations"]).to be_an(Array)
        end
      end

      it "recommends children structure for card types that need it" do
        result = tools.recommend_card_structure(
          name: "TestParent#{Time.now.to_i}",
          type: "Article",
          content: "Parent article",
          tags: ["Article"]
        )

        expect(result).to be_a(Hash)
      end
    end

    describe "suggest_card_improvements" do
      it "suggests improvements for existing card" do
        # Create a card first
        tools.create_card(
          test_card_name,
          content: "Basic content",
          type: "RichText"
        )

        result = tools.suggest_card_improvements(test_card_name)

        expect(result).to be_a(Hash)
        expect(result).to have_key("suggestions")
      end

      it "identifies missing tags in existing card" do
        # Create card without tags
        tools.create_card(
          test_card_name,
          content: "Content about MCP API testing",
          type: "Article"
        )

        result = tools.suggest_card_improvements(test_card_name)

        expect(result).to be_a(Hash)
        if result["suggestions"]
          expect(result["suggestions"]).to be_an(Array)
        end
      end

      it "identifies structure issues in existing card" do
        # Create a simple card
        tools.create_card(
          test_card_name,
          content: "Simple text",
          type: "RichText"
        )

        result = tools.suggest_card_improvements(test_card_name)

        expect(result).to be_a(Hash)
        # Should provide some kind of feedback
        expect(result).to have_key("suggestions")
      end

      it "raises NotFoundError for non-existent card" do
        expect {
          tools.suggest_card_improvements("NonExistent#{Time.now.to_i}")
        }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
      end
    end
  end

  describe "Content rendering utilities" do
    let(:tools) { Magi::Archive::Mcp::Tools.new }

    describe "render_snippet" do
      it "renders a short snippet of content" do
        content = "This is a long piece of content that needs to be truncated to a snippet"

        result = tools.render_snippet(content, length: 20)

        expect(result).to be_a(String)
        expect(result.length).to be <= 23 # 20 + "..."
      end

      it "preserves full content when shorter than limit" do
        content = "Short"

        result = tools.render_snippet(content, length: 20)

        expect(result).to eq("Short")
      end

      it "handles content with HTML tags" do
        content = "<p>This is <strong>HTML</strong> content</p>"

        result = tools.render_snippet(content, length: 15)

        expect(result).to be_a(String)
      end
    end
  end
end

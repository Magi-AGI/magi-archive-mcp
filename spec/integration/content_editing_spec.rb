# frozen_string_literal: true

require "spec_helper"
require_relative "../support/integration_helpers"

# Integration tests for content editing tools
#
# Tests: append_content, prepend_content, find_and_replace, find_in_card,
#        get_card_outline, submit_feedback
#
# Run with: INTEGRATION_TEST=true bundle exec rspec spec/integration/content_editing_spec.rb
RSpec.describe "Content Editing Tools", :integration do
  let(:tools) { Magi::Archive::Mcp::Tools.new }
  let(:test_prefix) { "ContentEditTest#{Time.now.to_i}" }

  before do
    skip "Integration tests disabled" unless ENV["INTEGRATION_TEST"]
  end

  after do
    cleanup_test_cards
  end

  # Helper to track created cards for cleanup
  def cleanup_test_cards
    return unless @created_cards

    @created_cards.each do |name|
      tools.delete_card(name) rescue nil
    end
  end

  def create_test_card(name, content: "Initial content", type: "RichText")
    @created_cards ||= []
    @created_cards << name
    tools.create_card(name, content: content, type: type)
  end

  describe "append_content" do
    it "appends content to end of card" do
      card_name = "#{test_prefix}_Append"
      create_test_card(card_name, content: "<p>First paragraph</p>")
      sleep 0.5

      result = tools.append_content(card_name, content: "<p>Second paragraph</p>", separator: "\n")
      expect(result["name"]).to eq(card_name)

      # Verify content was appended
      card = tools.get_card(card_name)
      expect(card["content"]).to include("First paragraph")
      expect(card["content"]).to include("Second paragraph")
    end

    it "appends without separator by default" do
      card_name = "#{test_prefix}_AppendNoSep"
      create_test_card(card_name, content: "AAA")
      sleep 0.5

      tools.append_content(card_name, content: "BBB")

      card = tools.get_card(card_name)
      expect(card["content"]).to include("AAABBB")
    end

    it "works with HTML content" do
      card_name = "#{test_prefix}_AppendHTML"
      create_test_card(card_name, content: "<h1>Title</h1>")
      sleep 0.5

      tools.append_content(card_name, content: "<p>Body text</p>", separator: "\n")

      card = tools.get_card(card_name)
      expect(card["content"]).to include("<h1>Title</h1>")
      expect(card["content"]).to include("<p>Body text</p>")
    end

    it "returns 404 for nonexistent card" do
      expect {
        tools.append_content("#{test_prefix}_Nonexistent", content: "text")
      }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
    end
  end

  describe "prepend_content" do
    it "prepends content to beginning of card" do
      card_name = "#{test_prefix}_Prepend"
      create_test_card(card_name, content: "<p>Original content</p>")
      sleep 0.5

      tools.prepend_content(card_name, content: "<p>New header</p>", separator: "\n")

      card = tools.get_card(card_name)
      content = card["content"]
      # New header should come before original
      header_pos = content.index("New header")
      original_pos = content.index("Original content")
      expect(header_pos).to be < original_pos
    end

    it "works with wiki link content" do
      card_name = "#{test_prefix}_PrependLinks"
      create_test_card(card_name, content: "[[Existing Link]]")
      sleep 0.5

      tools.prepend_content(card_name, content: "[[New Link]]\n")

      card = tools.get_card(card_name)
      expect(card["content"]).to include("[[New Link]]")
      expect(card["content"]).to include("[[Existing Link]]")
    end
  end

  describe "find_and_replace" do
    it "replaces first occurrence by default" do
      card_name = "#{test_prefix}_FindReplace"
      create_test_card(card_name, content: "<p>apple banana apple cherry</p>")
      sleep 0.5

      tools.find_and_replace(card_name, find: "apple", replace: "ORANGE")

      card = tools.get_card(card_name)
      content = card["content"]
      expect(content).to include("ORANGE")
      # Second "apple" should still be there
      expect(content).to include("apple")
      # First occurrence should be replaced
      expect(content.index("ORANGE")).to be < content.index("apple")
    end

    it "replaces all occurrences with occurrence: all" do
      card_name = "#{test_prefix}_FindReplaceAll"
      create_test_card(card_name, content: "<p>cat and cat and cat</p>")
      sleep 0.5

      tools.find_and_replace(card_name, find: "cat", replace: "dog", occurrence: "all")

      card = tools.get_card(card_name)
      expect(card["content"]).not_to include("cat")
      expect(card["content"].scan("dog").length).to eq(3)
    end

    it "replaces last occurrence with occurrence: last" do
      card_name = "#{test_prefix}_FindReplaceLast"
      create_test_card(card_name, content: "A-B-A-B-A")
      sleep 0.5

      tools.find_and_replace(card_name, find: "A", replace: "X", occurrence: "last")

      card = tools.get_card(card_name)
      content = card["content"]
      # Last A should be replaced
      expect(content).to end_with("X")
      # First two As should remain
      expect(content.scan("A").length).to eq(2)
    end

    it "raises error when text not found" do
      card_name = "#{test_prefix}_FindReplaceNotFound"
      create_test_card(card_name, content: "<p>Hello world</p>")
      sleep 0.5

      expect {
        tools.find_and_replace(card_name, find: "nonexistent text xyz", replace: "new")
      }.to raise_error(Magi::Archive::Mcp::Client::APIError, /not found/i)
    end

    it "handles HTML tag replacement" do
      card_name = "#{test_prefix}_FindReplaceHTML"
      create_test_card(card_name, content: "<h2>Old Title</h2>\n<p>Content here</p>")
      sleep 0.5

      tools.find_and_replace(card_name, find: "<h2>Old Title</h2>", replace: "<h2>New Title</h2>")

      card = tools.get_card(card_name)
      expect(card["content"]).to include("<h2>New Title</h2>")
      expect(card["content"]).not_to include("Old Title")
    end
  end

  describe "find_in_card" do
    it "finds text and returns matching excerpts with context" do
      card_name = "#{test_prefix}_FindInCard"
      long_content = "<p>This is a long card with lots of content. " \
                     "The quick brown fox jumps over the lazy dog. " \
                     "More filler text here to create distance. " \
                     "Another mention of the quick brown fox appears here.</p>"
      create_test_card(card_name, content: long_content)
      sleep 0.5

      result = tools.find_in_card(card_name, query: "quick brown fox")

      expect(result["card"]).to eq(card_name)
      expect(result["match_count"]).to eq(2)
      expect(result["matches"].length).to eq(2)
      expect(result["matches"].first).to have_key("position")
      expect(result["matches"].first).to have_key("context")
      expect(result["matches"].first["context"]).to include("quick brown fox")
    end

    it "returns zero matches for nonexistent text" do
      card_name = "#{test_prefix}_FindInCardEmpty"
      create_test_card(card_name, content: "<p>Simple content</p>")
      sleep 0.5

      result = tools.find_in_card(card_name, query: "nonexistent xyz 123")

      expect(result["match_count"]).to eq(0)
      expect(result["matches"]).to be_empty
    end

    it "respects context_chars parameter" do
      card_name = "#{test_prefix}_FindInCardContext"
      # Create content with a target word surrounded by lots of text
      padding = "x" * 200
      create_test_card(card_name, content: "#{padding}TARGET#{padding}")
      sleep 0.5

      # Small context
      result_small = tools.find_in_card(card_name, query: "TARGET", context_chars: 10)
      small_context = result_small["matches"].first["context"]

      # Large context
      result_large = tools.find_in_card(card_name, query: "TARGET", context_chars: 100)
      large_context = result_large["matches"].first["context"]

      # Larger context should return more surrounding text
      expect(large_context.length).to be > small_context.length
    end

    it "finds HTML tags" do
      card_name = "#{test_prefix}_FindInCardHTML"
      create_test_card(card_name, content: "<p>Key info here</p><p>Other stuff</p>")
      sleep 0.5

      result = tools.find_in_card(card_name, query: "Key info")
      expect(result["match_count"]).to eq(1)
    end
  end

  describe "get_card_outline" do
    it "returns heading structure for HTML content" do
      card_name = "#{test_prefix}_Outline"
      content = "<h1>Main Title</h1>\n<p>Intro text</p>\n" \
                "<h2>Section One</h2>\n<p>Content</p>\n" \
                "<h2>Section Two</h2>\n<p>More content</p>\n" \
                "<h3>Subsection</h3>\n<p>Details</p>"
      create_test_card(card_name, content: content)
      sleep 0.5

      result = tools.get_card_outline(card_name)

      expect(result["card"]).to eq(card_name)
      expect(result["type"]).to eq("RichText")
      expect(result["content_length"]).to be > 0
      expect(result["headings"].length).to eq(4)

      # Check heading levels
      levels = result["headings"].map { |h| h["level"] }
      expect(levels).to eq([1, 2, 2, 3])

      # Check heading text
      texts = result["headings"].map { |h| h["text"] }
      expect(texts).to include("Main Title", "Section One", "Section Two", "Subsection")
    end

    it "returns empty headings for cards without structure" do
      card_name = "#{test_prefix}_OutlineFlat"
      create_test_card(card_name, content: "<p>Just a plain paragraph with no headings at all.</p>")
      sleep 0.5

      result = tools.get_card_outline(card_name)

      expect(result["headings"]).to be_empty
      expect(result["content_length"]).to be > 0
    end

    it "returns 404 for nonexistent card" do
      expect {
        tools.get_card_outline("#{test_prefix}_NonexistentOutline")
      }.to raise_error(Magi::Archive::Mcp::Client::NotFoundError)
    end
  end

  describe "submit_feedback" do
    it "submits feedback to the log card" do
      # This may create the MCP Agent Feedback+log card if it doesn't exist
      result = tools.submit_feedback(
        category: "other",
        message: "Integration test feedback - #{test_prefix}",
        tool_name: "integration_test"
      )

      # Should succeed (either append or create)
      expect(result).to have_key("name")
    end
  end

  describe "combined workflows" do
    it "find_in_card then find_and_replace workflow" do
      card_name = "#{test_prefix}_Workflow"
      create_test_card(card_name, content: "<p>The project uses Ruby 2.7 for development.</p>")
      sleep 0.5

      # First, find what we need to change
      search = tools.find_in_card(card_name, query: "Ruby 2.7")
      expect(search["match_count"]).to eq(1)

      # Then replace it
      tools.find_and_replace(card_name, find: "Ruby 2.7", replace: "Ruby 3.4")

      # Verify the change
      card = tools.get_card(card_name)
      expect(card["content"]).to include("Ruby 3.4")
      expect(card["content"]).not_to include("Ruby 2.7")
    end

    it "outline then targeted append workflow" do
      card_name = "#{test_prefix}_OutlineAppend"
      create_test_card(card_name, content: "<h1>Report</h1>\n<p>Content here</p>")
      sleep 0.5

      # Check outline first
      outline = tools.get_card_outline(card_name)
      expect(outline["headings"].length).to eq(1)

      # Append a new section
      tools.append_content(card_name,
                           content: "\n<h2>New Section</h2>\n<p>Additional content</p>",
                           separator: "\n")

      # Verify outline updated
      new_outline = tools.get_card_outline(card_name)
      expect(new_outline["headings"].length).to eq(2)
    end
  end
end

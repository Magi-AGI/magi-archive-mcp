# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for suggesting tags based on card content and type
          class SuggestTags < ::MCP::Tool
            description "Suggest relevant tags for a card based on its content, name, and type. Useful for maintaining consistent tagging across the wiki."

            input_schema(
              properties: {
                card_name: {
                  type: "string",
                  description: "Name of an existing card to analyze (will read its content)"
                },
                content: {
                  type: "string",
                  description: "Card content to analyze (alternative to card_name)"
                },
                type: {
                  type: "string",
                  description: "Card type for context-aware suggestions"
                },
                limit: {
                  type: "integer",
                  description: "Maximum number of tag suggestions",
                  default: 10,
                  minimum: 1,
                  maximum: 20
                }
              },
              required: []
            )

            class << self
              def call(card_name: nil, content: nil, type: nil, limit: 10, server_context:)
                tools = server_context[:magi_tools]

                # Get card content if card_name provided
                if card_name
                  card = tools.get_card(card_name)
                  content ||= card["content"]
                  type ||= card["type"]
                end

                return error_response("Either card_name or content must be provided") unless content

                # Extract keywords and suggest tags
                suggestions = analyze_content_for_tags(content, card_name, type, limit)

                # Get existing tags for comparison if card_name provided
                existing_tags = card_name ? tools.get_card_tags(card_name) : []

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_suggestions(suggestions, existing_tags, card_name)
                }])
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: Card '#{card_name}' not found"
                }], is_error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error suggesting tags: #{e.message}"
                }], is_error: true)
              end

              private

              def error_response(message)
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: #{message}"
                }], is_error: true)
              end

              def analyze_content_for_tags(content, name, type, limit)
                suggestions = []

                # Extract capitalized words and phrases (likely proper nouns/concepts)
                words = content.to_s.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/)
                                    .map(&:strip)
                                    .select { |w| w.length > 2 }
                                    .uniq

                # Score words by frequency
                word_freq = words.group_by(&:itself).transform_values(&:count)
                sorted_words = word_freq.sort_by { |_, count| -count }.map(&:first)

                # Add frequent words as tag suggestions
                suggestions.concat(sorted_words.first(limit))

                # Type-based suggestions
                if type
                  case type.downcase
                  when "species"
                    suggestions << "Biology" << "Xenobiology" << "Alien"
                  when "faction"
                    suggestions << "Politics" << "Organization" << "Military"
                  when "technology", "tech"
                    suggestions << "Technology" << "Science" << "Engineering"
                  when "gm", "gamemaster"
                    suggestions << "GM" << "Secret" << "Plot"
                  end
                end

                # Name-based suggestions
                if name
                  # Extract hierarchy from compound card names
                  if name.include?("+")
                    parts = name.split("+")
                    # First part is often a category
                    suggestions << parts.first if parts.first
                  end
                end

                suggestions.uniq.first(limit)
              end

              def format_suggestions(suggestions, existing_tags, card_name)
                parts = []

                if card_name
                  parts << "# Tag Suggestions for '#{card_name}'"
                else
                  parts << "# Tag Suggestions"
                end
                parts << ""

                if existing_tags.any?
                  parts << "**Current Tags:** #{existing_tags.join(', ')}"
                  parts << ""
                end

                parts << "**Suggested Tags:**"
                parts << ""

                if suggestions.any?
                  suggestions.each_with_index do |tag, idx|
                    status = existing_tags.include?(tag) ? "✓ (already tagged)" : "+"
                    parts << "#{idx + 1}. #{tag} #{status}"
                  end
                else
                  parts << "No tag suggestions generated."
                  parts << ""
                  parts << "**Tip:** Content may need more specific terminology or the card type may benefit from manual tag selection."
                end

                parts.join("\n")
              end
            end
          end
        end
      end
    end
  end
end

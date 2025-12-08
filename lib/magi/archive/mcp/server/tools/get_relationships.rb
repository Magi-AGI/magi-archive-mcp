# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for getting card relationships
          class GetRelationships < ::MCP::Tool
            description "Get relationship information for a card (referers, links, nests, etc.)"

            input_schema(
              properties: {
                card_name: {
                  type: "string",
                  description: "The name of the card"
                },
                relationship_type: {
                  type: "string",
                  enum: ["referers", "linked_by", "nested_in", "nests", "links"],
                  description: "Type of relationship to fetch"
                }
              },
              required: ["card_name", "relationship_type"]
            )

            class << self
              def call(card_name:, relationship_type:, server_context:)
                tools = server_context[:magi_tools]

                result = case relationship_type
                        when "referers"
                          tools.get_referers(card_name)
                        when "linked_by"
                          tools.get_linked_by(card_name)
                        when "nested_in"
                          tools.get_nested_in(card_name)
                        when "nests"
                          tools.get_nests(card_name)
                        when "links"
                          tools.get_links(card_name)
                        end

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_relationships(card_name, relationship_type, result)
                }])
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: Card '#{card_name}' not found"
                }], error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error getting relationships: #{e.message}"
                }], error: true)
              end

              private

              def format_relationships(card_name, rel_type, result)
                # Get the appropriate key from the result
                key = case rel_type
                     when "referers" then "referers"
                     when "linked_by" then "linked_by"
                     when "nested_in" then "nested_in"
                     when "nests" then "nests"
                     when "links" then "links"
                     end

                cards = result[key] || []
                count_key = "#{key}_count"
                count = result[count_key] || cards.size

                parts = []
                parts << "# #{rel_type.capitalize} for #{card_name}"
                parts << ""
                parts << "**Found:** #{count} cards"
                parts << ""

                if cards.any?
                  cards.each_with_index do |card, idx|
                    parts << "#{idx + 1}. **#{card['name']}** (#{card['type']})"
                  end
                else
                  parts << "No #{rel_type} found for this card."
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

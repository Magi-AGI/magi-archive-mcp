# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for getting tags (all tags or tags for a specific card)
          class GetTags < ::MCP::Tool
            description "Get all tags in the system or tags for a specific card"

            input_schema(
              properties: {
                card_name: {
                  type: "string",
                  description: "Card name to get tags for (omit to get all tags)"
                },
                limit: {
                  type: "integer",
                  description: "Maximum number of tags to return (only for all tags)",
                  default: 100,
                  minimum: 1,
                  maximum: 500
                }
              },
              required: []
            )

            class << self
              def call(card_name: nil, limit: 100, server_context:)
                tools = server_context[:magi_tools]

                if card_name
                  tags = tools.get_card_tags(card_name)
                  ::MCP::Tool::Response.new([{
                    type: "text",
                    text: format_card_tags(card_name, tags)
                  }])
                else
                  tags = tools.get_all_tags(limit: limit)
                  ::MCP::Tool::Response.new([{
                    type: "text",
                    text: format_all_tags(tags)
                  }])
                end
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: Card '#{card_name}' not found"
                }], error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error getting tags: #{e.message}"
                }], error: true)
              end

              private

              def format_card_tags(card_name, tags)
                parts = []
                parts << "# Tags for #{card_name}"
                parts << ""

                if tags.any?
                  parts << "**#{tags.size} tags:**"
                  parts << ""
                  tags.each { |tag| parts << "- #{tag}" }
                else
                  parts << "No tags found for this card."
                end

                parts.join("\n")
              end

              def format_all_tags(tags)
                cards = tags || []

                parts = []
                parts << "# All Tags"
                parts << ""

                if cards.any?
                  parts << "**#{cards.size} tags found:**"
                  parts << ""
                  cards.each_with_index do |tag, idx|
                    parts << "#{idx + 1}. #{tag['name']}"
                  end
                else
                  parts << "No tags found in the system."
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

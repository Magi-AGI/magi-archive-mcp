# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # ChatGPT-compatible fetch tool that wraps get_card
          # Returns full document content in the format expected by ChatGPT connectors
          class Fetch < ::MCP::Tool
            description "Retrieve complete card content by ID (card name) for detailed analysis and citation. Returns the full text, title, and URL."

            input_schema(
              properties: {
                id: {
                  type: "string",
                  description: "Card name/ID from search results (e.g., 'Main Page' or 'Business Plan+Executive Summary')"
                }
              },
              required: ["id"]
            )

            class << self
              def call(arguments:, context:)
                id = arguments["id"]
                magi_tools = context[:magi_tools]

                # Use get_card to fetch the full card
                card = magi_tools.client.get_card(id)

                # Transform to ChatGPT connector format
                result = {
                  id: card[:name],
                  title: card[:name],
                  text: card[:content] || "No content available",
                  url: "https://wiki.magi-agi.org/#{card[:name].gsub(' ', '_')}",
                  metadata: {
                    type: card[:type],
                    created_at: card[:created_at],
                    updated_at: card[:updated_at]
                  }.compact
                }

                # Return as MCP content array with JSON-encoded text
                # This is the format ChatGPT connectors expect
                [
                  {
                    type: "text",
                    text: JSON.generate(result)
                  }
                ]
              rescue => e
                ErrorFormatter.format_error(e, "fetch")
              end
            end
          end
        end
      end
    end
  end
end

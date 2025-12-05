# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for searching cards in the wiki
          class SearchCards < ::MCP::Tool
            description "Search for cards in the Magi Archive wiki by query, type, or other filters"

            input_schema(
              properties: {
                query: {
                  type: "string",
                  description: "Search query (searches in card names)"
                },
                type: {
                  type: "string",
                  description: "Filter by card type (e.g., 'Article', 'Basic', 'Species')"
                },
                limit: {
                  type: "integer",
                  description: "Maximum number of results to return",
                  default: 50,
                  minimum: 1,
                  maximum: 100
                },
                offset: {
                  type: "integer",
                  description: "Number of results to skip (for pagination)",
                  default: 0,
                  minimum: 0
                }
              },
              required: []
            )

            class << self
              def call(query: nil, type: nil, limit: 50, offset: 0, server_context:)
                tools = server_context[:magi_tools]

                params = { limit: limit, offset: offset }
                params[:q] = query if query
                params[:type] = type if type

                results = tools.search_cards(**params)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_results(results)
                }])
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authorization_error("search", "cards", required_role: "user")
                }], is_error: true)
              rescue Client::AuthenticationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authentication_error(e.message)
                }], is_error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("searching cards", e)
                }], is_error: true)
              end

              private

              def format_results(results)
                cards = results["cards"] || []
                total = results["total"] || 0
                offset = results["offset"] || 0
                next_offset = results["next_offset"]

                parts = []
                parts << "# Search Results"
                parts << ""
                parts << "Found #{total} total cards, showing #{cards.size} starting at offset #{offset}"
                parts << ""

                if cards.any?
                  cards.each_with_index do |card, idx|
                    parts << "#{offset + idx + 1}. **#{card['name']}** (#{card['type']})"
                    parts << "   ID: #{card['id']}, Updated: #{card['updated_at']}" if card['updated_at']
                  end
                else
                  parts << "No cards found matching the search criteria."
                end

                if next_offset
                  parts << ""
                  parts << "---"
                  parts << "More results available. Use offset: #{next_offset} to fetch next page."
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

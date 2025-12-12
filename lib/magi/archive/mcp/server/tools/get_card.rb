# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for fetching a single card from the wiki
          class GetCard < ::MCP::Tool
            description "Get a single card by name from the Magi Archive wiki. Note: Pointer cards contain references to other cards (use list_children to see them). Search cards contain dynamic queries (content shows query, not results). Use underscores for exact name matches."

            annotations(
              read_only_hint: true,
              destructive_hint: false
            )

            input_schema(
              properties: {
                name: {
                  type: "string",
                  description: "The name of the card to fetch (e.g., 'Main Page' or 'Business Plan+Executive Summary')"
                },
                with_children: {
                  type: "boolean",
                  description: "Include child cards in the response",
                  default: false
                }
              },
              required: ["name"]
            )

            class << self
              def call(name:, with_children: false, server_context:)
                tools = server_context[:magi_tools]

                card = tools.get_card(name, with_children: with_children)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_card(card)
                }])
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.not_found("Card", name)
                }], error: true)
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authorization_error("view", name, required_role: "gm")
                }], error: true)
              rescue Client::AuthenticationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authentication_error(e.message)
                }], error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("fetching card '#{name}'", e)
                }], error: true)
              end

              private

              def format_card(card)
                parts = []
                parts << "# #{card['name']}"
                parts << ""
                parts << "**Type:** #{card['type']}"
                parts << "**ID:** #{card['id']}" if card['id']
                parts << "**Updated:** #{card['updated_at']}" if card['updated_at']
                parts << "**URL:** #{card['url']}" if card['url']
                parts << ""
                parts << "## Content"
                parts << ""
                parts << (card['content'] || '(empty)')

                # Add special note for Pointer and Search cards
                if card['type'] == 'Pointer'
                  parts << ""
                  parts << "**Note:** This is a Pointer card. Use list_children to see referenced cards, or get_card with with_children=true."
                elsif card['type'] == 'Search'
                  parts << ""
                  parts << "**Note:** This is a Search card. Content shows the search query. Results are dynamically generated when viewed on wiki."
                end

                # Add warning for virtual cards (empty junction cards)
                # Virtual cards are naming anchors - actual content is in compound child cards
                if card['virtual_card'] == true
                  parts << ""
                  parts << "**Warning:** This is a virtual/junction card with no content."
                  parts << "The actual content is likely in a compound child card with a full hierarchical path."
                  parts << "Search for cards containing '#{card['name']}' in their name to find the real content."
                  parts << "Example: If this is 'Trallox', look for 'Games+Butterfly Galaxii+...+Trallox'"
                end

                if card['children']&.any?
                  parts << ""
                  parts << "## Children (#{card['children'].size})"
                  parts << ""
                  card['children'].each do |child|
                    parts << "- #{child['name']} (#{child['type']})"
                  end
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

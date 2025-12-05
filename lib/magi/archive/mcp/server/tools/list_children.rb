# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for listing child cards
          class ListChildren < ::MCP::Tool
            # Alias Client for cleaner error handling
            Client = Magi::Archive::Mcp::Client
            description "List all child cards of a parent card"

            input_schema(
              properties: {
                parent_name: {
                  type: "string",
                  description: "The name of the parent card"
                },
                limit: {
                  type: "integer",
                  description: "Maximum number of children to return",
                  default: 50,
                  minimum: 1,
                  maximum: 100
                }
              },
              required: ["parent_name"]
            )

            class << self
              def call(parent_name:, limit: 50, server_context:)
                tools = server_context[:magi_tools]

                children = tools.list_children(parent_name, limit: limit)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_children(parent_name, children)
                }])
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.not_found("Card", parent_name)
                }], is_error: true)
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authorization_error("view children of", parent_name, required_role: "gm")
                }], is_error: true)
              rescue Client::AuthenticationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authentication_error(e.message)
                }], is_error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("listing children of '#{parent_name}'", e)
                }], is_error: true)
              end

              private

              def format_children(parent_name, children)
                parts = []
                parts << "# Children of #{parent_name}"
                parts << ""

                if children["children"]&.any?
                  total = children["total"] || children["children"].size
                  parts << "Found #{total} child cards:"
                  parts << ""

                  children["children"].each_with_index do |child, idx|
                    parts << "#{idx + 1}. **#{child['name']}** (#{child['type']})"
                    parts << "   ID: #{child['id']}, Updated: #{child['updated_at']}" if child['updated_at']
                  end
                else
                  parts << "No child cards found."
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

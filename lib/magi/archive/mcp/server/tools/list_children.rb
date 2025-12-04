# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for listing child cards
          class ListChildren < ::MCP::Tool
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
                  text: "Error: Parent card '#{parent_name}' not found"
                }], is_error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error listing children: #{e.message}"
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

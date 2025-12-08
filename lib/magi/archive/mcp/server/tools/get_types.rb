# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for listing card types
          class GetTypes < ::MCP::Tool
            description "List all card types available in the system"

            input_schema(
              properties: {
                limit: {
                  type: "integer",
                  description: "Maximum number of types to return",
                  default: 100,
                  minimum: 1,
                  maximum: 500
                }
              },
              required: []
            )

            class << self
              def call(limit: 100, server_context:)
                tools = server_context[:magi_tools]

                result = tools.list_types(limit: limit)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_types(result)
                }])
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error listing types: #{e.message}"
                }], error: true)
              end

              private

              def format_types(result)
                types = result["types"] || []
                total = result["total"] || types.size

                parts = []
                parts << "# Card Types"
                parts << ""
                parts << "**Total:** #{total} types"
                parts << ""

                if types.any?
                  types.each_with_index do |type, idx|
                    parts << "#{idx + 1}. **#{type['name']}**"
                    parts << "   ID: #{type['id']}" if type['id']
                  end
                else
                  parts << "No card types found."
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

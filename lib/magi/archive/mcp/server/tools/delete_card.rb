# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for deleting cards (admin only)
          class DeleteCard < ::MCP::Tool
            description "Delete a card from the Magi Archive wiki (requires admin role)"

            input_schema(
              properties: {
                name: {
                  type: "string",
                  description: "The name of the card to delete"
                },
                force: {
                  type: "boolean",
                  description: "Force delete even if card has children",
                  default: false
                }
              },
              required: ["name"]
            )

            class << self
              def call(name:, force: false, server_context:)
                tools = server_context[:magi_tools]

                result = tools.delete_card(name, force: force)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_deletion(name, result)
                }])
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: Card '#{name}' not found"
                }], is_error: true)
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: Admin role required to delete cards"
                }], is_error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error deleting card: #{e.message}"
                }], is_error: true)
              end

              private

              def format_deletion(name, result)
                parts = []
                parts << "# Card Deleted Successfully"
                parts << ""
                parts << "**Card:** #{name}"
                parts << ""
                parts << "The card has been permanently deleted from the wiki."
                parts << ""
                parts << "⚠️ **Warning:** This action cannot be undone."

                parts.join("\n")
              end
            end
          end
        end
      end
    end
  end
end

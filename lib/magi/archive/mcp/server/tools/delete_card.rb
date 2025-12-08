# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

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
                  text: ErrorFormatter.not_found("Card", name)
                }], error: true)
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authorization_error("delete", name, required_role: "admin")
                }], error: true)
              rescue Client::ValidationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.validation_error(e.message)
                }], error: true)
              rescue Client::AuthenticationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authentication_error(e.message)
                }], error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("deleting card '#{name}'", e)
                }], error: true)
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

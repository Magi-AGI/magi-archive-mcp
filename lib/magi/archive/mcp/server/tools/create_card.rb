# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for creating new cards
          class CreateCard < ::MCP::Tool
            description "Create a new card in the Magi Archive wiki"

            input_schema(
              properties: {
                name: {
                  type: "string",
                  description: "The name of the card to create (e.g., 'New Article' or 'Parent+Child')"
                },
                content: {
                  type: "string",
                  description: "The card content (HTML or plain text)"
                },
                type: {
                  type: "string",
                  description: "The card type (e.g., 'Article', 'Basic', 'RichText')",
                  default: "Basic"
                }
              },
              required: ["name"]
            )

            class << self
              def call(name:, content: nil, type: "Basic", server_context:)
                tools = server_context[:magi_tools]

                params = { type: type }
                params[:content] = content if content

                card = tools.create_card(name, **params)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_created_card(card)
                }])
              rescue Client::ValidationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Validation error: #{e.message}"
                }], is_error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error creating card: #{e.message}"
                }], is_error: true)
              end

              private

              def format_created_card(card)
                parts = []
                parts << "# Card Created Successfully"
                parts << ""
                parts << "**Name:** #{card['name']}"
                parts << "**Type:** #{card['type']}"
                parts << "**ID:** #{card['id']}" if card['id']
                parts << "**URL:** #{card['url']}" if card['url']
                parts << ""
                parts << "The card has been created and is now available on the wiki."

                parts.join("\n")
              end
            end
          end
        end
      end
    end
  end
end

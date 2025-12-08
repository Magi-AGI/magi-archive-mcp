# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for creating weekly summary cards
          class CreateWeeklySummary < ::MCP::Tool
            description "Generate and create a weekly summary card that combines wiki card changes and repository activity"

            input_schema(
              properties: {
                base_path: {
                  type: "string",
                  description: "Root directory to scan for git repositories (default: current directory)"
                },
                days: {
                  type: "integer",
                  description: "Number of days to look back for changes",
                  default: 7,
                  minimum: 1,
                  maximum: 365
                },
                date: {
                  type: "string",
                  description: "Date string for card name in 'YYYY MM DD' format (default: today)"
                },
                executive_summary: {
                  type: "string",
                  description: "Custom executive summary text (auto-generated if not provided)"
                },
                create_card: {
                  type: "boolean",
                  description: "Whether to create the card on the wiki (false returns preview only)",
                  default: true
                }
              },
              required: []
            )

            class << self
              def call(base_path: nil, days: 7, date: nil, executive_summary: nil, create_card: true, server_context:)
                tools = server_context[:magi_tools]

                # Get base path from server context if not provided
                base_path ||= server_context[:working_directory] || Dir.pwd

                params = {
                  base_path: base_path,
                  days: days,
                  create_card: create_card
                }
                params[:date] = date if date
                params[:executive_summary] = executive_summary if executive_summary

                result = tools.create_weekly_summary(**params)

                if create_card
                  # Result is the created card
                  ::MCP::Tool::Response.new([{
                    type: "text",
                    text: format_created_card(result)
                  }])
                else
                  # Result is the markdown preview
                  ::MCP::Tool::Response.new([{
                    type: "text",
                    text: "# Weekly Summary Preview\n\n#{result}"
                  }])
                end
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error creating weekly summary: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
                }], error: true)
              end

              private

              def format_created_card(card)
                parts = []
                parts << "# Weekly Summary Created Successfully"
                parts << ""
                parts << "**Card Name:** #{card['name']}"
                parts << "**Card ID:** #{card['id']}" if card['id']
                parts << "**URL:** #{card['url']}" if card['url']
                parts << ""
                parts << "The weekly summary has been created on the wiki and is ready to view."

                parts.join("\n")
              end
            end
          end
        end
      end
    end
  end
end

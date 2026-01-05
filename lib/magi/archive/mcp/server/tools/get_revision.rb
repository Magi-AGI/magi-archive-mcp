# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for fetching content from a specific card revision
          class GetRevision < ::MCP::Tool
            # Alias Client for cleaner error handling
            Client = Magi::Archive::Mcp::Client

            DESCRIPTION = <<~DESC.strip
              Get content from a specific revision of a card.

              Retrieves the full card state at a specific point in time,
              identified by the act_id from the revision history. This includes:
              - Card name, type, and content at that revision
              - When the revision was created
              - Who made the change

              Typical workflow:
              1. Use `get_card_history` to see all revisions and their act_ids
              2. Use `get_revision` with the desired act_id to see the content
              3. Use `restore_card` with the act_id to restore (admin only)

              This is useful for:
              - Comparing current content with a previous version
              - Recovering lost content without a full restore
              - Reviewing what content looked like at a specific date
            DESC

            description DESCRIPTION

            annotations(
              read_only_hint: true,
              destructive_hint: false
            )

            input_schema(
              properties: {
                name: {
                  type: "string",
                  description: "The name of the card"
                },
                act_id: {
                  type: "integer",
                  description: "The revision act ID (from get_card_history)"
                }
              },
              required: %w[name act_id]
            )

            class << self
              def call(name:, act_id:, server_context:)
                tools = server_context[:magi_tools]

                revision = tools.get_revision(name, act_id: act_id)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_revision(revision)
                }])
              rescue Client::NotFoundError
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.not_found("Revision", "#{name} (act_id: #{act_id})")
                }], error: true)
              rescue Client::AuthorizationError => e
                required_role = e.details&.dig("required_role") || "gm"
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authorization_error(
                    "view revision for", name,
                    required_role: required_role,
                    api_message: e.message,
                    api_details: e.details
                  )
                }], error: true)
              rescue Client::AuthenticationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authentication_error(e.message)
                }], error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("fetching revision #{act_id} for '#{name}'", e)
                }], error: true)
              end

              private

              def format_revision(revision)
                parts = []
                parts << "# Revision: #{revision['card']}"
                parts << ""
                parts << "**Act ID:** #{revision['act_id']}"
                parts << "**Date:** #{revision['acted_at']}"
                parts << "**Actor:** #{revision['actor'] || 'Unknown'}"
                parts << ""

                snapshot = revision["snapshot"] || {}

                parts << "## Snapshot at this Revision"
                parts << ""
                parts << "**Name:** #{snapshot['name']}"
                parts << "**Type:** #{snapshot['type']}"
                parts << ""
                parts << "### Content"
                parts << ""

                content = snapshot["content"]
                if content.nil? || content.to_s.strip.empty?
                  parts << "(empty)"
                else
                  parts << content
                end

                parts << ""
                parts << "---"
                parts << ""
                parts << "**To restore to this revision:** Use `restore_card` with"
                parts << "`name: \"#{revision['card']}\", act_id: #{revision['act_id']}`"
                parts << "(Requires admin role)"

                parts.join("\n")
              end
            end
          end
        end
      end
    end
  end
end

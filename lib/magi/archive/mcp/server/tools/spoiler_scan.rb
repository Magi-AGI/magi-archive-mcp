# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for running spoiler scans (GM/Admin only)
          class SpoilerScan < ::MCP::Tool
            # Alias Client for cleaner error handling
            Client = Magi::Archive::Mcp::Client

            description "Scan for spoiler terms leaking from GM/AI content to player content. GM or Admin role required. Reads spoiler terms from a terms card, scans player or AI content, and writes results to a results card."

            input_schema(
              properties: {
                terms_card: {
                  type: "string",
                  description: "Name of the card containing spoiler terms to check for (one term per line or [[term]] format)"
                },
                results_card: {
                  type: "string",
                  description: "Name of the card where results will be written"
                },
                scope: {
                  type: "string",
                  enum: ["player", "ai"],
                  description: "Scope to scan: 'player' (player-visible content) or 'ai' (AI content)",
                  default: "player"
                },
                limit: {
                  type: "integer",
                  description: "Maximum number of cards to scan per term",
                  default: 500,
                  minimum: 1,
                  maximum: 1000
                }
              },
              required: ["terms_card", "results_card"]
            )

            class << self
              def call(terms_card:, results_card:, scope: "player", limit: 500, server_context:)
                tools = server_context[:magi_tools]

                # Run the spoiler scan
                result = tools.client.post(
                  "/jobs/spoiler-scan",
                  terms_card: terms_card,
                  results_card: results_card,
                  scope: scope,
                  limit: limit
                )

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_scan_result(result)
                }])
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "❌ **Permission Denied**\n\nSpoiler scans require GM or Admin role.\n\nYour current role does not have permission to run spoiler scans. This operation is restricted to Game Masters and Administrators to prevent unauthorized access to sensitive content.\n\nRequired role: GM or Admin"
                }], error: true)
              rescue Client::ValidationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.validation_error(e.message)
                }], error: true)
              rescue Client::NotFoundError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: #{e.message}\n\nCheck that the terms_card name is correct and the card exists."
                }], error: true)
              rescue StandardError => e
                $stderr.puts "ERROR in spoiler_scan: #{e.class}: #{e.message}"
                $stderr.puts e.backtrace.first(5).join("\n")

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("spoiler scan", e)
                }], error: true)
              end

              private

              def format_scan_result(result)
                status = result["status"]
                matches = result["matches"] || 0
                results_card = result["results_card"]
                scope = result["scope"]
                terms_checked = result["terms_checked"] || 0

                parts = []
                parts << "# Spoiler Scan Complete"
                parts << ""

                if status == "completed"
                  if matches > 0
                    parts << "⚠️  **#{matches} potential spoiler(s) detected!**"
                  else
                    parts << "✅ **No spoilers detected** - all clear!"
                  end
                else
                  parts << "**Status:** #{status}"
                end

                parts << ""
                parts << "**Scope Scanned:** #{scope.capitalize} content"
                parts << "**Terms Checked:** #{terms_checked}"
                parts << "**Matches Found:** #{matches}"
                parts << ""
                parts << "**Results Card:** [[#{results_card}]]"
                parts << ""

                if matches > 0
                  parts << "---"
                  parts << ""
                  parts << "**Next Steps:**"
                  parts << "1. Review the results in [[#{results_card}]]"
                  parts << "2. Check each match to determine if it's a genuine spoiler"
                  parts << "3. Update player content to remove/rephrase spoilers"
                  parts << "4. Re-run scan to verify fixes"
                else
                  parts << "No action needed - player content appears clean."
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

# frozen_string_literal: true

require "mcp"
require_relative "../error_formatter"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for running safe CQL (Card Query Language) queries
          class RunQuery < ::MCP::Tool
            # Alias Client for cleaner error handling
            Client = Magi::Archive::Mcp::Client

            description "Run safe CQL (Card Query Language) queries with enforced limits. Supports searching by name, type, content, and dates."

            annotations(
              read_only_hint: true,
              destructive_hint: false
            )

            input_schema(
              properties: {
                query: {
                  type: "object",
                  description: "Query parameters (name, type, content, updated_at, created_at)",
                  properties: {
                    name: {
                      type: "string",
                      description: "Card name pattern (substring match)"
                    },
                    type: {
                      type: "string",
                      description: "Card type (exact match)"
                    },
                    content: {
                      type: "string",
                      description: "Content search pattern (substring match)"
                    }
                  }
                },
                limit: {
                  type: "integer",
                  description: "Maximum number of results",
                  default: 50,
                  minimum: 1,
                  maximum: 100
                },
                offset: {
                  type: "integer",
                  description: "Starting offset for pagination",
                  default: 0,
                  minimum: 0
                }
              },
              required: ["query"]
            )

            class << self
              def call(query:, limit: 50, offset: 0, server_context:)
                tools = server_context[:magi_tools]

                # Validate query
                return error_response("Query cannot be empty") if query.nil? || query.empty?

                # Run the query
                result = tools.client.post("/run_query", query: query, limit: limit, offset: offset)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_query_results(result)
                }])
              rescue Client::ValidationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.validation_error(e.message)
                }], error: true)
              rescue Client::AuthorizationError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.authorization_error("run query", "query", required_role: "user")
                }], error: true)
              rescue StandardError => e
                $stderr.puts "ERROR in run_query: #{e.class}: #{e.message}"
                $stderr.puts e.backtrace.first(5).join("\n")

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.generic_error("running query", e)
                }], error: true)
              end

              private

              def error_response(message)
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: #{message}"
                }], error: true)
              end

              def format_query_results(result)
                results = result["results"] || []
                total = result["total"] || 0
                limit = result["limit"] || 50
                offset = result["offset"] || 0

                parts = []
                parts << "# Query Results"
                parts << ""
                parts << "**Total Matches:** #{total}"
                parts << "**Showing:** #{results.size} (offset: #{offset}, limit: #{limit})"
                parts << ""

                if results.any?
                  parts << "## Results"
                  parts << ""
                  results.each_with_index do |card, idx|
                    parts << "#{offset + idx + 1}. **#{card['name']}** (#{card['type']})"
                    parts << "   - Updated: #{card['updated_at']}"
                    parts << ""
                  end

                  # Add pagination info
                  if result["next_offset"]
                    parts << "---"
                    parts << ""
                    parts << "**More results available.** Use offset: #{result['next_offset']} to see next page."
                  end
                else
                  parts << "No results found."
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

# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for content rendering and format conversion
          class RenderContent < ::MCP::Tool
            description "Convert content between HTML and Markdown formats"

            annotations(
              read_only_hint: true,
              destructive_hint: false
            )

            input_schema(
              properties: {
                content: {
                  type: "string",
                  description: "Content to convert"
                },
                from_format: {
                  type: "string",
                  enum: ["html", "markdown"],
                  description: "Source format"
                },
                to_format: {
                  type: "string",
                  enum: ["html", "markdown"],
                  description: "Target format"
                }
              },
              required: ["content", "from_format", "to_format"]
            )

            class << self
              def call(content:, from_format:, to_format:, server_context:)
                tools = server_context[:magi_tools]

                # Convert format strings to symbols
                from_sym = from_format.to_sym
                to_sym = to_format.to_sym

                result = tools.render_snippet(content, from: from_sym, to: to_sym)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_result(content, from_format, to_format, result)
                }])
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error rendering content: #{e.message}"
                }], error: true)
              end

              private

              def format_result(original, from_fmt, to_fmt, result)
                parts = []
                parts << "# Content Conversion"
                parts << ""
                parts << "**From:** #{from_fmt.upcase}"
                parts << "**To:** #{to_fmt.upcase}"
                parts << ""
                parts << "## Original Content"
                parts << ""
                parts << "```#{from_fmt}"
                parts << original
                parts << "```"
                parts << ""
                parts << "## Converted Content"
                parts << ""
                parts << "```#{to_fmt}"
                parts << result
                parts << "```"

                parts.join("\n")
              end
            end
          end
        end
      end
    end
  end
end

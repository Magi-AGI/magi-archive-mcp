# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for card validation
          class ValidateCard < ::MCP::Tool
            description "Validate a card's tags and structure based on its type"

            input_schema(
              properties: {
                type: {
                  type: "string",
                  description: "The card type to validate against"
                },
                tags: {
                  type: "array",
                  items: { type: "string" },
                  description: "Tags to validate",
                  default: []
                },
                name: {
                  type: "string",
                  description: "Card name for naming convention validation (optional)"
                },
                content: {
                  type: "string",
                  description: "Card content for content-based tag suggestions (optional)"
                },
                children: {
                  type: "array",
                  items: { type: "string" },
                  description: "Child card names for structure validation (optional)",
                  default: []
                }
              },
              required: ["type"]
            )

            class << self
              def call(type:, tags: [], name: nil, content: nil, children: [], server_context:)
                tools = server_context[:magi_tools]

                # Validate tags
                tag_validation = tools.validate_card_tags(type, tags, content: content, name: name)

                # Validate structure if children provided
                structure_validation = if children.any? || name
                                        tools.validate_card_structure(
                                          type,
                                          name: name || "New Card",
                                          has_children: children.any?,
                                          children_names: children
                                        )
                                      else
                                        nil
                                      end

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_validation(tag_validation, structure_validation)
                }])
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error validating card: #{e.message}"
                }], error: true)
              end

              private

              def format_validation(tag_val, struct_val)
                parts = []
                parts << "# Card Validation Results"
                parts << ""

                # Tag validation
                parts << "## Tag Validation"
                parts << ""
                parts << "**Status:** #{tag_val['valid'] ? '✅ Valid' : '❌ Invalid'}"
                parts << ""

                if tag_val["errors"]&.any?
                  parts << "**Errors:**"
                  tag_val["errors"].each { |err| parts << "- ❌ #{err}" }
                  parts << ""
                end

                if tag_val["warnings"]&.any?
                  parts << "**Warnings:**"
                  tag_val["warnings"].each { |warn| parts << "- ⚠️ #{warn}" }
                  parts << ""
                end

                if tag_val["required_tags"]&.any?
                  parts << "**Required Tags:** #{tag_val['required_tags'].join(', ')}"
                end

                if tag_val["suggested_tags"]&.any?
                  parts << "**Suggested Tags:** #{tag_val['suggested_tags'].join(', ')}"
                end

                # Structure validation
                if struct_val
                  parts << ""
                  parts << "## Structure Validation"
                  parts << ""
                  parts << "**Status:** #{struct_val['valid'] ? '✅ Valid' : '❌ Invalid'}"
                  parts << ""

                  if struct_val["errors"]&.any?
                    parts << "**Errors:**"
                    struct_val["errors"].each { |err| parts << "- ❌ #{err}" }
                    parts << ""
                  end

                  if struct_val["warnings"]&.any?
                    parts << "**Warnings:**"
                    struct_val["warnings"].each { |warn| parts << "- ⚠️ #{warn}" }
                  end
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

# frozen_string_literal: true

require "mcp"

module Magi
  module Archive
    module Mcp
      module Server
        module Tools
          # MCP Tool for getting card structure recommendations
          class GetRecommendations < ::MCP::Tool
            description "Get structure recommendations and improvement suggestions for cards"

            annotations(
              read_only_hint: true,
              destructive_hint: false
            )

            input_schema(
              properties: {
                operation: {
                  type: "string",
                  enum: ["requirements", "recommend_structure", "suggest_improvements"],
                  description: "Type of recommendation: 'requirements' for type rules, 'recommend_structure' for new card guidance, 'suggest_improvements' for existing card analysis"
                },
                type: {
                  type: "string",
                  description: "Card type (required for 'requirements' and 'recommend_structure')"
                },
                name: {
                  type: "string",
                  description: "Card name (required for 'recommend_structure' and 'suggest_improvements')"
                },
                tags: {
                  type: "array",
                  items: { type: "string" },
                  description: "Current tags (for 'recommend_structure')",
                  default: []
                },
                content: {
                  type: "string",
                  description: "Card content (for 'recommend_structure')"
                }
              },
              required: ["operation"]
            )

            class << self
              def call(operation:, type: nil, name: nil, tags: [], content: nil, server_context:)
                tools = server_context[:magi_tools]

                result = case operation
                        when "requirements"
                          return error_response("Type is required for requirements") unless type
                          tools.get_type_requirements(type)
                        when "recommend_structure"
                          return error_response("Type and name are required") unless type && name
                          tools.recommend_card_structure(type, name, tags: tags, content: content)
                        when "suggest_improvements"
                          return error_response("Name is required for improvements") unless name
                          tools.suggest_card_improvements(name)
                        end

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: format_recommendation(operation, result)
                }])
              rescue Client::NotFoundError => e
                card_ref = name || type || "unknown"
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: ErrorFormatter.not_found("Card", card_ref, operation: "get recommendations for")
                }], error: true)
              rescue StandardError => e
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error getting recommendations: #{e.message}"
                }], error: true)
              end

              private

              def error_response(message)
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: #{message}"
                }], error: true)
              end

              def format_recommendation(operation, result)
                case operation
                when "requirements"
                  format_requirements(result)
                when "recommend_structure"
                  format_structure_recommendation(result)
                when "suggest_improvements"
                  format_improvements(result)
                end
              end

              def format_requirements(result)
                parts = []
                parts << "# Type Requirements"
                parts << ""

                if result["required_tags"]&.any?
                  parts << "**Required Tags:** #{result['required_tags'].join(', ')}"
                else
                  parts << "**Required Tags:** None"
                end

                if result["suggested_tags"]&.any?
                  parts << "**Suggested Tags:** #{result['suggested_tags'].join(', ')}"
                end

                if result["required_children"]&.any?
                  parts << ""
                  parts << "**Required Children:**"
                  result["required_children"].each { |c| parts << "- #{c}" }
                end

                if result["suggested_children"]&.any?
                  parts << ""
                  parts << "**Suggested Children:**"
                  result["suggested_children"].each { |c| parts << "- #{c}" }
                end

                parts.join("\n")
              end

              def format_structure_recommendation(result)
                parts = []
                parts << "# Structure Recommendation for #{result['card_name']}"
                parts << ""
                parts << "**Type:** #{result['card_type']}"
                parts << ""

                if result["summary"]
                  parts << "## Summary"
                  parts << result["summary"]
                  parts << ""
                end

                # Tags
                if result["tags"]
                  parts << "## Recommended Tags"
                  parts << ""

                  if result["tags"]["required"]&.any?
                    parts << "**Required:** #{result['tags']['required'].join(', ')}"
                  end

                  if result["tags"]["suggested"]&.any?
                    parts << "**Suggested:** #{result['tags']['suggested'].join(', ')}"
                  end

                  if result["tags"]["content_based"]&.any?
                    parts << "**Content-based:** #{result['tags']['content_based'].join(', ')}"
                  end

                  parts << ""
                end

                # Children
                if result["children"]&.any?
                  parts << "## Recommended Child Cards"
                  parts << ""

                  result["children"].each do |child|
                    parts << "### #{child['name']}"
                    parts << "- **Type:** #{child['type']}"
                    parts << "- **Purpose:** #{child['purpose']}" if child['purpose']
                    parts << "- **Priority:** #{child['priority']}" if child['priority']
                    parts << ""
                  end
                end

                # Naming
                if result["naming"]
                  parts << "## Naming Conventions"
                  result["naming"].each { |n| parts << "- #{n}" }
                end

                parts.join("\n")
              end

              def format_improvements(result)
                parts = []
                parts << "# Improvement Suggestions for #{result['card_name']}"
                parts << ""
                parts << "**Type:** #{result['card_type']}"
                parts << ""

                if result["summary"]
                  parts << "## Summary"
                  parts << result["summary"]
                  parts << ""
                end

                if result["missing_children"]&.any?
                  parts << "## Missing Children"
                  result["missing_children"].each { |c| parts << "- #{c}" }
                  parts << ""
                end

                if result["missing_tags"]&.any?
                  parts << "## Missing Tags"
                  result["missing_tags"].each { |t| parts << "- #{t}" }
                  parts << ""
                end

                if result["suggested_additions"]&.any?
                  parts << "## Suggested Additions"
                  result["suggested_additions"].each { |a| parts << "- #{a}" }
                  parts << ""
                end

                if result["naming_issues"]&.any?
                  parts << "## Naming Issues"
                  result["naming_issues"].each { |i| parts << "- #{i}" }
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

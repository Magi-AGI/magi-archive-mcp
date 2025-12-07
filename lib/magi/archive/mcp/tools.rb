# frozen_string_literal: true

require "open3"
require_relative "client"

module Magi
  module Archive
    module Mcp
      # MCP Tools for Magi Archive operations
      #
      # Provides high-level tools for card retrieval, mutation, and management
      # that align with the MCP (Model Context Protocol) specification.
      #
      # @example Basic usage
      #   tools = Magi::Archive::Mcp::Tools.new
      #   card = tools.get_card("User")
      #   cards = tools.search_cards(q: "game", limit: 10)
      #   children = tools.list_children("Business Plan")
      class Tools
        attr_reader :client

        # Initialize tools with optional client
        #
        # @param client [Client, nil] optional HTTP client (creates new one if nil)
        def initialize(client = nil)
          @client = client || Client.new
        end

        # Get a single card by name
        #
        # Fetches a card with all its metadata, content, and optionally its children.
        #
        # @param name [String] the card name
        # @param with_children [Boolean] include child cards (default: false)
        # @return [Hash] card data with keys: name, content, type, id, url, etc.
        # @raise [Client::NotFoundError] if card doesn't exist
        # @raise [Client::AuthorizationError] if user lacks permission to view card
        #
        # @example
        #   card = tools.get_card("User")
        #   # => { "name" => "User", "content" => "...", "type" => "Cardtype", ... }
        #
        # @example With children
        #   card = tools.get_card("Business Plan", with_children: true)
        #   # => { "name" => "Business Plan", "children" => [...], ... }
        def get_card(name, with_children: false)
          params = {}
          params[:with_children] = true if with_children

          client.get("/cards/#{encode_card_name(name)}", **params)
        end

        # Search for cards
        #
        # Search cards by query string, optionally filtered by type.
        # Returns paginated results.
        #
        # IMPORTANT: The 'q' parameter performs substring search on CARD NAMES ONLY,
        # not card content. For content-based search, use get_card to retrieve cards
        # and search content locally, or use type filters to narrow results.
        #
        # @param q [String, nil] search query (searches card NAMES only, case-insensitive substring match)
        # @param type [String, nil] filter by card type (e.g., "User", "Role")
        # @param limit [Integer] results per page (default: 50, max: 100)
        # @param offset [Integer] starting offset (default: 0)
        # @return [Hash] with keys: cards (array), total, limit, offset, next_offset
        # @raise [Client::ValidationError] if parameters are invalid
        #
        # @example Simple search - finds cards with "game" in their name
        #   results = tools.search_cards(q: "game")
        #   results["cards"].each { |card| puts card["name"] }
        #
        # @example Search with type filter
        #   users = tools.search_cards(type: "User", limit: 20)
        #
        # @example Paginated search
        #   page1 = tools.search_cards(q: "plan", limit: 10, offset: 0)
        #   page2 = tools.search_cards(q: "plan", limit: 10, offset: 10)
        def search_cards(q: nil, type: nil, limit: 50, offset: 0)
          params = { limit: limit, offset: offset }
          params[:q] = q if q
          params[:type] = type if type

          client.get("/cards", **params)
        end

        # List all child cards of a parent
        #
        # Gets the children of a compound card (e.g., "Parent+Child" cards).
        # Per MCP-SPEC.md line 38: GET /api/mcp/cards/:name/children
        #
        # @param parent_name [String] the parent card name
        # @param limit [Integer] results per page (default: 50, max: 100)
        # @param offset [Integer] starting offset (default: 0)
        # @return [Hash] with keys: parent, children (array), depth, child_count
        # @raise [Client::NotFoundError] if parent card doesn't exist
        #
        # @example
        #   result = tools.list_children("Business Plan")
        #   result["children"].each { |child| puts child["name"] }
        #
        # @example Paginated
        #   page1 = tools.list_children("Game Master", limit: 20, offset: 0)
        def list_children(parent_name, limit: 50, offset: 0)
          params = { limit: limit, offset: offset }

          client.get("/cards/#{encode_card_name(parent_name)}/children", **params)
        end

        # Fetch all cards matching search criteria
        #
        # Automatically handles pagination and returns all matching cards.
        # Use with caution on large result sets.
        #
        # @param q [String, nil] search query
        # @param type [String, nil] filter by card type
        # @param limit [Integer] page size for fetching (default: 50)
        # @return [Array<Hash>] array of all matching cards
        #
        # @example
        #   all_users = tools.fetch_all_cards(type: "User")
        #   puts "Found #{all_users.length} users"
        def fetch_all_cards(q: nil, type: nil, limit: 50)
          params = {}
          params[:q] = q if q
          params[:type] = type if type

          client.fetch_all("/cards", limit: limit, **params)
        end

        # Iterate over card search results page by page
        #
        # Yields each page of results to the block. More memory-efficient
        # than fetch_all_cards for large result sets.
        #
        # @param q [String, nil] search query
        # @param type [String, nil] filter by card type
        # @param limit [Integer] page size (default: 50)
        # @yield [Array<Hash>] each page of cards
        # @return [Enumerator] if no block given
        #
        # @example
        #   tools.each_card_page(type: "User", limit: 20) do |page|
        #     page.each { |user| puts user["name"] }
        #   end
        def each_card_page(q: nil, type: nil, limit: 50, &)
          params = {}
          params[:q] = q if q
          params[:type] = type if type

          client.each_page("/cards", limit: limit, **params, &)
        end

        # Create a new card
        #
        # Creates a card with the specified name, content, and type.
        # Requires appropriate permissions (user role can create basic cards).
        #
        # @param name [String] the card name (required)
        # @param content [String, nil] the card content (optional)
        # @param type [String, nil] the card type (optional, defaults to "Basic")
        # @param metadata [Hash] additional card metadata (optional)
        # @return [Hash] created card data with id, name, url, etc.
        # @raise [Client::ValidationError] if parameters are invalid
        # @raise [Client::AuthorizationError] if user lacks permission
        #
        # @example Simple card
        #   card = tools.create_card("My Note", content: "Some notes here")
        #
        # @example With type
        #   user = tools.create_card("john_doe", type: "User", content: "John's profile")
        #
        # @example Compound card (child)
        #   child = tools.create_card("Parent+Child", content: "Child content")
        def create_card(name, content: nil, type: nil, **metadata)
          payload = { name: name }
          payload[:content] = content if content
          payload[:type] = type if type
          payload.merge!(metadata) if metadata.any?

          client.post("/cards", **payload)
        end

        # Update an existing card
        #
        # Updates card content and/or metadata. Only specified fields are changed.
        #
        # @param name [String] the card name
        # @param content [String, nil] new content (optional)
        # @param type [String, nil] new type (optional)
        # @param metadata [Hash] metadata updates (optional)
        # @return [Hash] updated card data
        # @raise [Client::NotFoundError] if card doesn't exist
        # @raise [Client::AuthorizationError] if user lacks permission
        #
        # @example Update content
        #   tools.update_card("My Note", content: "Updated content")
        #
        # @example Update type
        #   tools.update_card("john_doe", type: "Administrator")
        #
        # @example Update multiple fields
        #   tools.update_card("Profile", content: "New bio", visibility: "public")
        def update_card(name, content: nil, type: nil, **metadata)
          payload = {}
          payload[:content] = content if content
          payload[:type] = type if type
          payload.merge!(metadata) if metadata.any?

          raise ArgumentError, "No update parameters provided" if payload.empty?

          client.patch("/cards/#{encode_card_name(name)}", **payload)
        end

        # Delete a card
        #
        # Permanently deletes a card. This operation cannot be undone.
        # Requires admin role permissions.
        #
        # @param name [String] the card name
        # @param force [Boolean] force deletion even with children (default: false)
        # @return [Hash] deletion confirmation with success status
        # @raise [Client::NotFoundError] if card doesn't exist
        # @raise [Client::AuthorizationError] if user lacks admin permission
        # @raise [Client::ValidationError] if card has children and force=false
        #
        # @example Delete card
        #   tools.delete_card("Obsolete Card")
        #
        # @example Force delete with children
        #   tools.delete_card("Parent Card", force: true)
        def delete_card(name, force: false)
          path = "/cards/#{encode_card_name(name)}"
          path += "?force=true" if force

          client.delete(path)
        end

        # List all card types
        #
        # Gets all available card types in the system.
        # Returns paginated results.
        #
        # @param limit [Integer] results per page (default: 50, max: 100)
        # @param offset [Integer] starting offset (default: 0)
        # @return [Hash] with keys: types (array), total, limit, offset, next_offset
        #
        # @example
        #   types = tools.list_types
        #   types["types"].each { |type| puts type["name"] }
        #
        # @example Paginated
        #   page1 = tools.list_types(limit: 20, offset: 0)
        def list_types(limit: 50, offset: 0)
          params = { limit: limit, offset: offset }
          client.get("/types", **params)
        end

        # Get all types
        #
        # Fetches all card types across all pages.
        #
        # @return [Array<Hash>] array of all card types
        #
        # @example
        #   all_types = tools.fetch_all_types
        #   puts "Found #{all_types.length} card types"
        def fetch_all_types
          client.fetch_all("/types", limit: 50)
        end

        # Render snippet with format conversion
        #
        # Converts content between HTML and Markdown formats.
        # Per MCP-SPEC.md lines 39-40:
        #   - HTML→Markdown: POST /api/mcp/render → returns { markdown:, format: "gfm" }
        #   - Markdown→HTML: POST /api/mcp/render/markdown → returns { html:, format: "html" }
        #
        # @param content [String] the content to render
        # @param from [Symbol] source format (:html or :markdown)
        # @param to [Symbol] target format (:html or :markdown)
        # @return [Hash] server response with markdown: or html: key
        # @raise [ArgumentError] if from/to formats are invalid or the same
        #
        # @example HTML to Markdown
        #   result = tools.render_snippet("<p>Hello <strong>world</strong></p>", from: :html, to: :markdown)
        #   # => { "markdown" => "Hello **world**", "format" => "gfm" }
        #
        # @example Markdown to HTML
        #   result = tools.render_snippet("Hello **world**", from: :markdown, to: :html)
        #   # => { "html" => "<p>Hello <strong>world</strong></p>", "format" => "html" }
        def render_snippet(content, from:, to:)
          valid_formats = %i[html markdown]
          unless valid_formats.include?(from) && valid_formats.include?(to)
            raise ArgumentError, "Format must be :html or :markdown"
          end

          raise ArgumentError, "Source and target formats cannot be the same" if from == to

          # Route to correct endpoint based on conversion direction
          # Server returns different response keys: markdown: or html:
          endpoint = if from == :html && to == :markdown
                       "/render"
                     elsif from == :markdown && to == :html
                       "/render/markdown"
                     else
                       raise ArgumentError, "Unsupported conversion: #{from} to #{to}"
                     end

          payload = { content: content }

          client.post(endpoint, **payload)
        end

        # Execute batch operations on multiple cards
        #
        # Performs multiple card operations (create/update) in a single request.
        # Per MCP-SPEC.md line 67: payload uses 'ops' key, not 'operations'
        # Returns individual results for each operation with HTTP 207 Multi-Status.
        # Supports transactional mode where all operations succeed or all fail.
        #
        # @param operations [Array<Hash>] array of operation specs (each with :action, :name, etc.)
        # @param mode [String] execution mode: "per_item" (default) or "transactional"
        # @return [Hash] with keys: results (array of per-operation results), mode
        # @raise [Client::ValidationError] if operations are invalid
        #
        # @example Batch create
        #   ops = [
        #     { action: "create", name: "Card 1", content: "Content 1" },
        #     { action: "create", name: "Card 2", content: "Content 2" }
        #   ]
        #   results = tools.batch_operations(ops)
        #
        # @example Mixed operations
        #   ops = [
        #     { action: "update", name: "Card 1", content: "Updated" },
        #     { action: "create", name: "Card 2", content: "New content" }
        #   ]
        #   results = tools.batch_operations(ops)
        #
        # @example Transactional mode
        #   results = tools.batch_operations(ops, mode: "transactional")
        #   # All succeed or all fail (rollback)
        def batch_operations(operations, mode: "per_item")
          valid_modes = %w[per_item transactional]
          raise ArgumentError, "Mode must be 'per_item' or 'transactional'" unless valid_modes.include?(mode)

          payload = {
            ops: operations,
            mode: mode
          }

          client.post("/cards/batch", **payload)
        end

        # Build operation for creating a child card
        #
        # Convenience helper for building batch operation specs for child cards.
        # Child cards use Decko's compound card naming: "Parent+ChildName"
        #
        # @param parent_name [String] the parent card name
        # @param child_name [String] the child name (will be prefixed with parent+)
        # @param content [String, nil] child card content
        # @param type [String, nil] child card type
        # @return [Hash] operation spec for use with batch_operations
        #
        # @example Create single child
        #   op = tools.build_child_op("Business Plan", "Overview", content: "Summary here")
        #   tools.batch_operations([op])
        #
        # @example Create multiple children
        #   ops = [
        #     tools.build_child_op("Business Plan", "Overview", content: "Summary"),
        #     tools.build_child_op("Business Plan", "Goals", content: "Objectives"),
        #     tools.build_child_op("Business Plan", "Timeline", content: "Schedule")
        #   ]
        #   tools.batch_operations(ops)
        def build_child_op(parent_name, child_name, content: nil, type: nil)
          full_name = "#{parent_name}+#{child_name}"
          op = {
            action: "create",
            name: full_name
          }
          op[:content] = content if content
          op[:type] = type if type
          op
        end

        # === Validation Operations ===

        # Validate tags for a card
        #
        # Checks if the provided tags meet the requirements for the card type.
        # Returns validation errors and warnings.
        #
        # @param type [String] the card type
        # @param tags [Array<String>] the tags to validate
        # @param content [String, nil] optional card content for content-based suggestions
        # @param name [String, nil] optional card name for naming convention checks
        # @return [Hash] validation result with valid, errors, warnings keys
        #
        # @example
        #   result = tools.validate_card_tags(
        #     "Game Master Document",
        #     ["Game", "Species"],
        #     content: "This is GM-only content",
        #     name: "Secret Plot+GM"
        #   )
        #   if result["valid"]
        #     puts "Tags are valid!"
        #   else
        #     puts "Errors: #{result['errors'].join(', ')}"
        #   end
        def validate_card_tags(type, tags, content: nil, name: nil)
          payload = { type: type, tags: tags }
          payload[:content] = content if content
          payload[:name] = name if name

          client.post("/validation/tags", **payload)
        end

        # Validate card structure
        #
        # Checks if the card structure meets the requirements for the card type.
        # Returns validation errors and warnings about missing children.
        #
        # @param type [String] the card type
        # @param name [String, nil] the card name
        # @param has_children [Boolean] whether the card will have children
        # @param children_names [Array<String>] names of planned children
        # @return [Hash] validation result with valid, errors, warnings keys
        #
        # @example
        #   result = tools.validate_card_structure(
        #     "Species",
        #     name: "Vulcans",
        #     has_children: true,
        #     children_names: ["Vulcans+traits", "Vulcans+description"]
        #   )
        #   puts "Warnings: #{result['warnings'].join(', ')}" if result['warnings'].any?
        def validate_card_structure(type, name: nil, has_children: false, children_names: [])
          payload = {
            type: type,
            has_children: has_children,
            children_names: children_names
          }
          payload[:name] = name if name

          client.post("/validation/structure", **payload)
        end

        # Get requirements for a card type
        #
        # Returns the tag and structure requirements for a specific card type.
        #
        # @param type [String] the card type
        # @return [Hash] requirements with required_tags, suggested_tags, required_children, suggested_children
        #
        # @example
        #   reqs = tools.get_type_requirements("Species")
        #   puts "Required tags: #{reqs['required_tags'].join(', ')}"
        #   puts "Suggested children: #{reqs['suggested_children'].join(', ')}"
        def get_type_requirements(type)
          client.get("/validation/requirements/#{type}")
        end

        # Create card with validation
        #
        # Validates tags and structure before creating a card.
        # Returns validation errors if validation fails.
        #
        # @param name [String] the card name
        # @param content [String, nil] the card content
        # @param type [String, nil] the card type
        # @param tags [Array<String>] tags for the card
        # @param validate [Boolean] whether to validate before creating (default: true)
        # @param metadata [Hash] additional card metadata
        # @return [Hash] created card data or validation errors
        #
        # @example
        #   result = tools.create_card_with_validation(
        #     "New Species",
        #     type: "Species",
        #     tags: ["Game", "Alien"],
        #     content: "A new alien species"
        #   )
        def create_card_with_validation(name, content: nil, type: nil, tags: [], validate: true, **metadata)
          if validate && type
            # Validate tags first
            validation = validate_card_tags(type, tags, content: content, name: name)

            unless validation["valid"]
              return {
                "status" => "validation_failed",
                "errors" => validation["errors"],
                "warnings" => validation["warnings"]
              }
            end

            # Log warnings if any
            if validation["warnings"]&.any?
              warn "Validation warnings: #{validation['warnings'].join(', ')}"
            end
          end

          # Use batch operations with transactional mode for atomic creation
          # This ensures both card and tags are created together or not at all
          operations = []

          # Main card creation
          operations << {
            action: "create",
            name: name,
            content: content,
            type: type
          }.merge(metadata).compact

          # Add tags card if tags provided
          if tags.any?
            tags_content = tags.map { |tag| "[[#{tag}]]" }.join("\n")
            operations << {
              action: "create",
              name: "#{name}+tags",
              content: tags_content,
              type: "Pointer"
            }
          end

          # Execute as atomic transaction
          result = batch_operations(operations, mode: "transactional")

          # Return the main card from batch results
          main_card_result = result["results"]&.first
          return main_card_result["card"] if main_card_result&.dig("status") == "success"

          # If batch failed, return error details
          {
            "status" => "error",
            "message" => result["message"] || "Failed to create card with tags",
            "errors" => result["results"]&.map { |r| r["error"] }&.compact || []
          }
        end

        # Get structure recommendations for a card
        #
        # Returns comprehensive structure recommendations including:
        # - Recommended child cards
        # - Suggested tags
        # - Naming conventions
        #
        # @param type [String] the card type
        # @param name [String] the card name
        # @param tags [Array<String>] proposed tags
        # @param content [String] proposed content
        # @return [Hash] recommendations with children, tags, naming sections
        #
        # @example
        #   recs = tools.recommend_card_structure(
        #     "Species",
        #     "Vulcans",
        #     tags: ["Star Trek", "Humanoid"],
        #     content: "Logical and stoic species..."
        #   )
        #   recs["children"].each { |child| puts "Create: #{child['name']}" }
        def recommend_card_structure(type, name, tags: [], content: "")
          payload = {
            type: type,
            name: name,
            tags: tags,
            content: content
          }

          client.post("/validation/recommend_structure", **payload)
        end

        # Suggest improvements for an existing card
        #
        # Analyzes an existing card and suggests structural improvements:
        # - Missing required children
        # - Missing required tags
        # - Suggested additions
        # - Naming issues
        #
        # @param card_name [String] the card name to analyze
        # @return [Hash] improvement suggestions
        #
        # @example
        #   improvements = tools.suggest_card_improvements("Vulcans")
        #   puts improvements["summary"]
        #   improvements["missing_children"].each do |child|
        #     puts "Missing: #{child['suggestion']}"
        #   end
        def suggest_card_improvements(card_name)
          client.post("/validation/suggest_improvements", name: card_name)
        end

        # === Tag Search Operations ===

        # Search cards by tag
        #
        # Searches for cards that have the specified tag.
        # Tags in Decko are typically stored as pointer cards (CardName+tags).
        #
        # @param tag_name [String] the tag to search for
        # @param limit [Integer] maximum results (default: 50)
        # @param offset [Integer] starting offset (default: 0)
        # @return [Hash] search results with cards array
        #
        # @example
        #   results = tools.search_by_tag("Article")
        #   results["cards"].each { |card| puts card["name"] }
        def search_by_tag(tag_name, limit: 50, offset: 0)
          # Search for cards with +tags subcard containing the tag
          search_cards(q: "tags:#{tag_name}", limit: limit, offset: offset)
        end

        # Search cards by multiple tags (AND logic)
        #
        # Searches for cards that have all of the specified tags.
        #
        # @param tags [Array<String>] tags to search for
        # @param limit [Integer] maximum results (default: 50)
        # @param offset [Integer] starting offset (default: 0)
        # @return [Hash] search results with cards array
        #
        # @example
        #   results = tools.search_by_tags(["Article", "Published"])
        #   results["cards"].each { |card| puts card["name"] }
        def search_by_tags(tags, limit: 50, offset: 0)
          # Search using tag query for each tag (AND logic)
          query = tags.map { |tag| "tags:#{tag}" }.join(" AND ")
          search_cards(q: query, limit: limit, offset: offset)
        end

        # Get all tags used in the system
        #
        # Returns all unique tags across all cards.
        # This fetches cards of type "Tag" or searches for +tags subcards.
        #
        # @param limit [Integer] maximum results (default: 100)
        # @return [Array<Hash>] array of tag cards
        #
        # @example
        #   tags = tools.get_all_tags
        #   tags.each { |tag| puts tag["name"] }
        def get_all_tags(limit: 100)
          # Try to fetch all Tag type cards
          result = search_cards(type: "Tag", limit: limit)
          result["cards"] || []
        rescue Client::APIError
          # Fallback: search for cards ending with +tags
          result = search_cards(q: "*+tags", limit: limit)
          result["cards"] || []
        end

        # Get tags for a specific card
        #
        # Returns the tags associated with the specified card.
        # Looks for a CardName+tags subcard.
        #
        # @param card_name [String] the card name
        # @return [Array<String>] array of tag names
        #
        # @example
        #   tags = tools.get_card_tags("Main Page")
        #   puts "Tags: #{tags.join(', ')}"
        def get_card_tags(card_name)
          tags_card = get_card("#{card_name}+tags")

          # Parse tags from content (usually pointer format)
          content = tags_card["content"] || ""

          # Tags can be in various formats:
          # - [[Tag1]], [[Tag2]]
          # - Simple list with newlines
          parse_tags_from_content(content)
        rescue Client::NotFoundError
          # No tags card exists
          []
        end

        # Search cards by tag pattern
        #
        # Searches for cards with tags matching a pattern.
        #
        # @param pattern [String] tag pattern to match (e.g., "game-*")
        # @param limit [Integer] maximum results (default: 50)
        # @return [Hash] search results with cards array
        #
        # @example
        #   results = tools.search_by_tag_pattern("game-*")
        #   results["cards"].each { |card| puts card["name"] }
        def search_by_tag_pattern(pattern, limit: 50)
          # Search for tags matching pattern
          tag_results = search_cards(q: pattern, type: "Tag", limit: limit)
          tag_names = (tag_results["cards"] || []).map { |c| c["name"] }

          # Search for cards with any of these tags
          return { "cards" => [], "total" => 0 } if tag_names.empty?

          search_by_tags_any(tag_names, limit: limit)
        end

        # Search cards by any of the specified tags (OR logic)
        #
        # Searches for cards that have at least one of the specified tags.
        #
        # @param tags [Array<String>] tags to search for
        # @param limit [Integer] maximum results (default: 50)
        # @return [Hash] search results with cards array
        #
        # @example
        #   results = tools.search_by_tags_any(["Article", "Draft"])
        #   results["cards"].each { |card| puts card["name"] }
        def search_by_tags_any(tags, limit: 50)
          # Search using tag query for any tag (OR logic)
          query = tags.map { |tag| "tags:#{tag}" }.join(" OR ")
          search_cards(q: query, limit: limit)
        end

        # === Card Relationship Operations ===

        # Get cards that reference/link to this card
        #
        # Returns cards that contain references to the specified card.
        # Includes both explicit links [[CardName]] and nests {{CardName}}.
        #
        # @param card_name [String] the card name
        # @return [Hash] with keys: card, referers (array), referer_count
        # @raise [Client::NotFoundError] if card doesn't exist
        #
        # @example
        #   result = tools.get_referers("Main Page")
        #   result["referers"].each { |card| puts card["name"] }
        def get_referers(card_name)
          client.get("/cards/#{encode_card_name(card_name)}/referers")
        end

        # Get cards that nest/include this card
        #
        # Returns cards that include this card using nest syntax {{CardName}}.
        #
        # @param card_name [String] the card name
        # @return [Hash] with keys: card, nested_in (array), nested_in_count
        # @raise [Client::NotFoundError] if card doesn't exist
        #
        # @example
        #   result = tools.get_nested_in("Template Card")
        #   result["nested_in"].each { |card| puts card["name"] }
        def get_nested_in(card_name)
          client.get("/cards/#{encode_card_name(card_name)}/nested_in")
        end

        # Get cards that this card nests/includes
        #
        # Returns cards that are nested in this card using {{CardName}} syntax.
        #
        # @param card_name [String] the card name
        # @return [Hash] with keys: card, nests (array), nests_count
        # @raise [Client::NotFoundError] if card doesn't exist
        #
        # @example
        #   result = tools.get_nests("Main Page")
        #   result["nests"].each { |card| puts card["name"] }
        def get_nests(card_name)
          client.get("/cards/#{encode_card_name(card_name)}/nests")
        end

        # Get cards that this card links to
        #
        # Returns cards that are linked from this card using [[CardName]] syntax.
        #
        # @param card_name [String] the card name
        # @return [Hash] with keys: card, links (array), links_count
        # @raise [Client::NotFoundError] if card doesn't exist
        #
        # @example
        #   result = tools.get_links("Main Page")
        #   result["links"].each { |card| puts card["name"] }
        def get_links(card_name)
          client.get("/cards/#{encode_card_name(card_name)}/links")
        end

        # Get cards that link to this card
        #
        # Returns cards that link to this card using [[CardName]] syntax.
        #
        # @param card_name [String] the card name
        # @return [Hash] with keys: card, linked_by (array), linked_by_count
        # @raise [Client::NotFoundError] if card doesn't exist
        #
        # @example
        #   result = tools.get_linked_by("Main Page")
        #   result["linked_by"].each { |card| puts card["name"] }
        def get_linked_by(card_name)
          client.get("/cards/#{encode_card_name(card_name)}/linked_by")
        end

        # === Admin Operations ===

        # Download database backup (admin only)
        #
        # Creates and downloads a database backup file.
        # Requires admin role permissions.
        #
        # @param save_path [String, nil] optional local path to save backup file
        # @return [String] backup file content or path if saved
        # @raise [Client::AuthorizationError] if user lacks admin permission
        #
        # @example Download to file
        #   tools.download_database_backup(save_path: "/tmp/backup.sql")
        #
        # @example Get backup content
        #   backup_content = tools.download_database_backup
        def download_database_backup(save_path: nil)
          response = client.get_raw("/admin/database/backup")

          if save_path
            File.write(save_path, response.body)
            save_path
          else
            response.body
          end
        end

        # List available database backups (admin only)
        #
        # Returns list of available backup files with metadata.
        # Requires admin role permissions.
        #
        # @return [Hash] with keys: backups (array), total, backup_dir
        # @raise [Client::AuthorizationError] if user lacks admin permission
        #
        # @example
        #   backups = tools.list_database_backups
        #   backups["backups"].each do |backup|
        #     puts "#{backup['filename']} - #{backup['size_human']} - #{backup['age']}"
        #   end
        def list_database_backups
          client.get("/admin/database/backup/list")
        end

        # Download specific database backup file (admin only)
        #
        # Downloads a previously created backup file by filename.
        # Requires admin role permissions.
        #
        # @param filename [String] the backup filename
        # @param save_path [String, nil] optional local path to save backup file
        # @return [String] backup file content or path if saved
        # @raise [Client::AuthorizationError] if user lacks admin permission
        # @raise [Client::NotFoundError] if backup file doesn't exist
        #
        # @example
        #   tools.download_database_backup_file(
        #     "magi_archive_backup_20251203_120000.sql",
        #     save_path: "/tmp/backup.sql"
        #   )
        def download_database_backup_file(filename, save_path: nil)
          response = client.get_raw("/admin/database/backup/download/#{filename}")

          if save_path
            File.write(save_path, response.body)
            save_path
          else
            response.body
          end
        end

        # Delete database backup file (admin only)
        #
        # Deletes a specific backup file from the server.
        # Requires admin role permissions.
        #
        # @param filename [String] the backup filename to delete
        # @return [Hash] deletion confirmation
        # @raise [Client::AuthorizationError] if user lacks admin permission
        # @raise [Client::NotFoundError] if backup file doesn't exist
        #
        # @example
        #   tools.delete_database_backup("magi_archive_backup_20251203_120000.sql")
        def delete_database_backup(filename)
          client.delete("/admin/database/backup/#{filename}")
        end

        private

        # Parse tags from content string
        #
        # Extracts tag names from various Decko tag formats:
        # - [[Tag1]], [[Tag2]] (pointer format)
        # - Tag1\nTag2\n (line-separated)
        #
        # @param content [String] the content to parse
        # @return [Array<String>] extracted tag names
        def parse_tags_from_content(content)
          tags = []

          # Extract [[...]] format
          content.scan(/\[\[([^\]]+)\]\]/) do |match|
            tags << match[0].strip
          end

          # If no bracket tags found, try line-separated
          if tags.empty?
            tags = content.split(/[\n,]/).map(&:strip).reject(&:empty?)
          end

          tags.uniq
        end

        # URL-encode card name for safe use in paths
        #
        # Per MCP-SPEC.md line 14: encode spaces and reserved chars, keep + literal
        # Encodes all RFC 3986 reserved characters except + (used for card hierarchy)
        #
        # @param name [String] the card name
        # @return [String] URL-encoded name
        def encode_card_name(name)
          # Encode all characters except: A-Z a-z 0-9 - _ . ~ +
          # Keep + literal for Decko compound cards (e.g., "Parent+Child")
          name.chars.map do |char|
            if char.match?(/[A-Za-z0-9\-_.~+]/)
              char
            else
              format("%%%02X", char.ord)
            end
          end.join
        end
      end

      # === Weekly Summary Operations ===

      # Get cards updated within a date range
      #
      # Retrieves all cards that have been updated within the specified time period.
      # Useful for generating weekly summaries or tracking recent changes.
      #
      # @param days [Integer] number of days to look back (default: 7)
      # @param since [Time, String, nil] specific start date (overrides days)
      # @param before [Time, String, nil] specific end date (default: now)
      # @param limit [Integer] maximum results per page (default: 100)
      # @return [Array<Hash>] array of updated cards with metadata
      #
      # @example Get cards updated in last week
      #   changes = tools.get_recent_changes(days: 7)
      #   changes.each { |card| puts "#{card['name']} - #{card['updated_at']}" }
      #
      # @example Get cards updated in specific date range
      #   changes = tools.get_recent_changes(
      #     since: "2025-11-25",
      #     before: "2025-12-02"
      #   )
      def get_recent_changes(days: 7, since: nil, before: nil, limit: 100)
        since_time = since ? parse_time(since) : (Time.now - (days * 24 * 60 * 60))
        before_time = before ? parse_time(before) : Time.now

        all_cards = []
        offset = 0
        loop_count = 0
        max_loops = 100 # Safety limit to prevent infinite loops

        loop do
          # Safety check: prevent infinite loop if server has pagination bug
          loop_count += 1
          if loop_count > max_loops
            warn "Pagination safety limit reached (#{max_loops} pages). " \
                 "Possible server pagination bug. Returning #{all_cards.size} cards so far."
            break
          end

          result = search_cards(
            updated_since: since_time.iso8601,
            updated_before: before_time.iso8601,
            limit: limit,
            offset: offset
          )

          cards = result["cards"] || []
          break if cards.empty?

          all_cards.concat(cards)
          offset = result["next_offset"]
          break unless offset
        end

        # Sort by updated_at descending (most recent first)
        all_cards.sort_by { |c| c["updated_at"] || "" }.reverse
      end

      # Scan git repositories for changes
      #
      # Scans all git repositories under the specified base path for commits
      # made within the specified time period. Useful for generating weekly
      # summaries of development activity.
      #
      # @param base_path [String, nil] root directory to scan (default: current directory)
      # @param days [Integer] number of days to look back (default: 7)
      # @param since [Time, String, nil] specific start date (overrides days)
      # @return [Hash] repository changes grouped by repo name
      #
      # @example Scan repos in current directory
      #   changes = tools.scan_git_repos(days: 7)
      #   changes.each do |repo, commits|
      #     puts "#{repo}: #{commits.size} commits"
      #   end
      #
      # @example Scan specific directory
      #   changes = tools.scan_git_repos(
      #     base_path: "/path/to/projects",
      #     days: 7
      #   )
      def scan_git_repos(base_path: nil, days: 7, since: nil)
        base_path ||= Dir.pwd
        since_time = since ? parse_time(since) : (Time.now - (days * 24 * 60 * 60))
        since_str = since_time.strftime("%Y-%m-%d")

        repos = find_git_repos(base_path)
        changes = {}

        repos.each do |repo_path|
          repo_name = File.basename(repo_path)
          commits = get_git_commits(repo_path, since: since_str)

          changes[repo_name] = commits unless commits.empty?
        end

        changes
      end

      # Format weekly summary markdown
      #
      # Creates formatted markdown content for a weekly summary card,
      # following the standard Weekly Work Summary format used in the wiki.
      #
      # @param card_changes [Array<Hash>] cards updated during the period
      # @param repo_changes [Hash] repository changes grouped by repo name
      # @param title [String, nil] custom title (default: auto-generated from date)
      # @param executive_summary [String, nil] custom executive summary
      # @return [String] formatted markdown content
      #
      # @example Basic usage
      #   cards = tools.get_recent_changes(days: 7)
      #   repos = tools.scan_git_repos(days: 7)
      #   markdown = tools.format_weekly_summary(cards, repos)
      #
      # @example With custom title and summary
      #   markdown = tools.format_weekly_summary(
      #     cards, repos,
      #     title: "Weekly Work Summary 2025 12 09",
      #     executive_summary: "Focused on MCP API enhancements..."
      #   )
      def format_weekly_summary(card_changes, repo_changes, title: nil, executive_summary: nil)
        date_str = Time.now.strftime("%Y %m %d")
        title ||= "Weekly Work Summary #{date_str}"

        summary = []
        summary << "# #{title}\n\n"

        # Executive Summary
        summary << "## Executive Summary\n\n"
        if executive_summary
          summary << "#{executive_summary}\n\n"
        else
          summary << "This week saw #{card_changes.size} card updates across the wiki"
          summary << " and #{repo_changes.values.sum(&:size)} commits across #{repo_changes.size} repositories.\n\n"
        end

        # Wiki Card Updates
        if card_changes.any?
          summary << "## Wiki Card Updates\n\n"
          summary << format_card_changes(card_changes)
          summary << "\n"
        end

        # Repository Changes
        if repo_changes.any?
          summary << "## Repository & Code Changes\n\n"
          summary << format_repo_changes(repo_changes)
          summary << "\n"
        end

        # Next Steps placeholder
        summary << "## Next Steps\n\n"
        summary << "- [Add your next steps here]\n"
        summary << "- \n"
        summary << "- \n\n"

        summary.join
      end

      # Create weekly summary card
      #
      # Convenience method that combines all steps: fetches recent changes,
      # scans repositories, formats the summary, and creates the card.
      #
      # @param base_path [String, nil] root directory for repo scanning (default: current dir)
      # @param days [Integer] number of days to look back (default: 7)
      # @param date [String, nil] date string for card name (default: today)
      # @param executive_summary [String, nil] custom executive summary
      # @param parent [String] parent card name (default: "Home")
      # @param create_card [Boolean] whether to create the card (default: true, false returns content only)
      # @return [Hash, String] created card data or markdown content if create_card is false
      #
      # @example Create this week's summary
      #   card = tools.create_weekly_summary
      #
      # @example Create summary for specific period
      #   card = tools.create_weekly_summary(
      #     days: 7,
      #     date: "2025 12 09",
      #     executive_summary: "Focused on MCP API Phase 2.1 completion..."
      #   )
      #
      # @example Generate content without creating card
      #   markdown = tools.create_weekly_summary(create_card: false)
      #   puts markdown
      def create_weekly_summary(base_path: nil, days: 7, date: nil, executive_summary: nil, parent: "Home", create_card: true)
        # Get date string for card name
        date_str = date || Time.now.strftime("%Y %m %d")
        card_name = "Weekly Work Summary #{date_str}"

        # Fetch recent changes
        card_changes = get_recent_changes(days: days)
        repo_changes = scan_git_repos(base_path: base_path, days: days)

        # Format summary
        content = format_weekly_summary(
          card_changes,
          repo_changes,
          title: card_name,
          executive_summary: executive_summary
        )

        # Return content only if requested
        return content unless create_card

        # Create the card
        card = self.create_card(
          card_name,
          content: content,
          type: "Basic"
        )

        # Add to parent hierarchy if specified
        if parent
          begin
            # Get parent card to verify it exists
            parent_card = get_card(parent)

            # Create a link in the parent card (simplified approach)
            # Could enhance this to add to a specific section
          rescue Client::NotFoundError
            # Parent doesn't exist, that's okay
          end
        end

        card
      end

      private

      # Parse time from various formats
      def parse_time(time_input)
        return time_input if time_input.is_a?(Time)

        Time.parse(time_input.to_s)
      end

      # Find all git repositories under a path
      def find_git_repos(base_path)
        repos = []

        # Check if base_path itself is a git repo
        if File.directory?(File.join(base_path, ".git"))
          repos << base_path
        end

        # Find subdirectories with .git folders (limit depth to avoid deep scanning)
        Dir.glob(File.join(base_path, "*", ".git")).each do |git_dir|
          repos << File.dirname(git_dir)
        end

        Dir.glob(File.join(base_path, "*", "*", ".git")).each do |git_dir|
          repos << File.dirname(git_dir)
        end

        repos.uniq
      end

      # Get git commits for a repository since a date
      def get_git_commits(repo_path, since:)
        # Use Open3.capture3 for safer command execution with timeout
        stdout, stderr, status = Open3.capture3(
          "git", "log",
          "--since=#{since}",
          "--pretty=format:%h|%an|%ad|%s",
          "--date=short",
          chdir: repo_path,
          timeout: 30 # Prevent hanging on huge repos
        )

        # Return empty if command failed
        return [] unless status.success?

        # Parse output into structured commits
        stdout.split("\n").map do |line|
          hash, author, date, subject = line.split("|", 4)
          {
            "hash" => hash,
            "author" => author,
            "date" => date,
            "subject" => subject
          }
        end
      rescue Timeout::Error
        warn "Git log timed out for #{repo_path}. Skipping this repo."
        []
      rescue StandardError => e
        # If we can't read the repo, return empty
        warn "Failed to read git commits from #{repo_path}: #{e.message}"
        []
      end

      # Format card changes for summary
      def format_card_changes(cards)
        lines = []

        # Group by card type or hierarchy level
        grouped = cards.group_by do |card|
          # Group by top-level parent if it's a compound card
          if card["name"].include?("+")
            card["name"].split("+").first
          else
            "Top Level"
          end
        end

        grouped.each do |group, group_cards|
          if group != "Top Level"
            lines << "### #{group}\n\n"
          end

          group_cards.each do |card|
            # Format: `Card Name+Subcard` - brief description
            card_path = "`#{card['name']}`"
            updated = card["updated_at"] ? " (#{format_date(card['updated_at'])})" : ""
            lines << "- #{card_path}#{updated}\n"
          end

          lines << "\n"
        end

        lines.join
      end

      # Format repository changes for summary
      def format_repo_changes(repo_changes)
        lines = []

        repo_changes.each do |repo_name, commits|
          lines << "### #{repo_name}\n\n"
          lines << "**#{commits.size} commit#{commits.size == 1 ? '' : 's'}**\n\n"

          commits.first(10).each do |commit|
            lines << "- `#{commit['hash']}` #{commit['subject']} (#{commit['author']}, #{commit['date']})\n"
          end

          if commits.size > 10
            lines << "- ... and #{commits.size - 10} more commits\n"
          end

          lines << "\n"
        end

        lines.join
      end

      # Format date for display
      def format_date(date_str)
        Time.parse(date_str).strftime("%Y-%m-%d")
      rescue StandardError
        date_str
      end
    end
  end
end

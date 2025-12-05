# frozen_string_literal: true

module Magi
  module Archive
    module Mcp
      module Server
        # Formats client errors into helpful messages for AI agents
        #
        # Provides context-aware error messages that help AI agents understand:
        # - What went wrong
        # - Why it happened
        # - What to try next
        module ErrorFormatter
          # Format a NotFoundError with helpful suggestions
          #
          # @param resource_type [String] type of resource (e.g., "Card", "Type")
          # @param name [String] the name that wasn't found
          # @return [String] formatted error message
          def self.not_found(resource_type, name)
            parts = []
            parts << "❌ **#{resource_type} Not Found**"
            parts << ""
            parts << "**Searched for:** `#{name}`"
            parts << ""
            parts << "**Possible reasons:**"
            parts << "- The #{resource_type.downcase} may not exist in the wiki"
            parts << "- Card names are case-sensitive - check capitalization"
            parts << "- Spaces vs underscores matter: 'Main Page' ≠ 'Main_Page'"

            if name.include?("+")
              parts << "- For compound cards, ensure parent exists: '#{name.split('+').first}'"
            else
              parts << "- For child cards, use format: 'Parent+Child' (with + sign)"
            end

            parts << ""
            parts << "**Try these steps:**"
            parts << "1. Use `search_cards` to find cards with similar names"
            parts << "2. Check the wiki directly: https://wiki.magi-agi.org/#{name.gsub(' ', '_')}"
            parts << "3. List available cards with `search_cards(limit: 20)`"

            parts.join("\n")
          end

          # Format an AuthorizationError with role information
          #
          # @param operation [String] the operation attempted (e.g., "view", "delete")
          # @param resource [String] what was being accessed
          # @param required_role [String, nil] role needed (if known)
          # @param current_role [String, nil] current user role (if available)
          # @return [String] formatted error message
          def self.authorization_error(operation, resource, required_role: nil, current_role: nil)
            parts = []
            parts << "🔒 **Permission Denied**"
            parts << ""
            parts << "**Operation:** #{operation.capitalize} '#{resource}'"

            if required_role
              parts << "**Required role:** #{required_role}"
            end

            if current_role
              parts << "**Your current role:** #{current_role}"
            end

            parts << ""
            parts << "**What this means:**"

            case required_role
            when "admin"
              parts << "- This operation requires administrator privileges"
              parts << "- Only users with the 'Administrator' role can perform this action"
              parts << "- Contact a wiki administrator if you need this access"
            when "gm"
              parts << "- This content is marked as GM (Game Master) only"
              parts << "- Regular players cannot view GM-restricted content"
              parts << "- This is intentional to prevent spoilers"
            else
              parts << "- You don't have permission to #{operation} this #{resource}"
              parts << "- This may be GM-only content or admin-restricted"
            end

            parts << ""
            parts << "**Possible solutions:**"
            parts << "- Request the appropriate role from a wiki administrator"
            parts << "- Check if you're authenticated with the correct account"
            parts << "- For read-only tasks, the 'user' role should be sufficient"

            parts.join("\n")
          end

          # Format a ValidationError with parameter guidance
          #
          # @param message [String] the validation error message
          # @param field [String, nil] the field that failed validation
          # @param valid_values [Array, nil] list of valid values (if applicable)
          # @return [String] formatted error message
          def self.validation_error(message, field: nil, valid_values: nil)
            parts = []
            parts << "⚠️ **Validation Error**"
            parts << ""
            parts << message

            if field
              parts << ""
              parts << "**Problem field:** `#{field}`"
            end

            if valid_values&.any?
              parts << ""
              parts << "**Valid values:**"
              valid_values.each { |v| parts << "- `#{v}`" }
            end

            parts << ""
            parts << "**Tips:**"
            parts << "- Check the tool's input schema for required parameters"
            parts << "- Ensure all required fields are provided"
            parts << "- Verify parameter types match expectations (string, boolean, etc.)"

            parts.join("\n")
          end

          # Format an authentication error
          #
          # @param message [String] the auth error message
          # @return [String] formatted error message
          def self.authentication_error(message)
            parts = []
            parts << "🔑 **Authentication Error**"
            parts << ""
            parts << message
            parts << ""
            parts << "**Common causes:**"
            parts << "- JWT token has expired (tokens expire after 1 hour)"
            parts << "- Invalid credentials in MCP_USERNAME/MCP_PASSWORD"
            parts << "- API key is invalid or revoked"
            parts << ""
            parts << "**Solution:**"
            parts << "- The MCP server will automatically refresh your token"
            parts << "- If the error persists, check your environment variables"
            parts << "- Verify credentials at: https://wiki.magi-agi.org"

            parts.join("\n")
          end

          # Format a server error with troubleshooting steps
          #
          # @param operation [String] what operation failed
          # @param message [String] the error message
          # @param exception_class [String, nil] the exception class name
          # @return [String] formatted error message
          def self.server_error(operation, message, exception_class: nil)
            parts = []
            parts << "💥 **Server Error**"
            parts << ""
            parts << "**Operation:** #{operation}"
            parts << "**Error:** #{message}"

            if exception_class
              parts << "**Type:** #{exception_class}"
            end

            parts << ""
            parts << "**What to try:**"
            parts << "1. Retry the operation (may be a temporary issue)"
            parts << "2. Check if the server is accessible: https://wiki.magi-agi.org"
            parts << "3. Simplify the request (smaller limit, fewer parameters)"
            parts << "4. If error persists, this may be a server-side bug"
            parts << ""
            parts << "**Reporting:**"
            parts << "If this error continues, please report it with:"
            parts << "- The exact operation you were attempting"
            parts << "- The full error message above"
            parts << "- Any relevant card names or parameters"

            parts.join("\n")
          end

          # Format a generic error with context
          #
          # @param context [String] what was being attempted
          # @param error [StandardError] the exception
          # @return [String] formatted error message
          def self.generic_error(context, error)
            parts = []
            parts << "❌ **Error: #{context}**"
            parts << ""
            parts << error.message
            parts << ""

            # Add specific guidance based on error message patterns
            if error.message.include?("Connection") || error.message.include?("timeout")
              parts << "**Network Issue Detected:**"
              parts << "- Check your internet connection"
              parts << "- Verify wiki.magi-agi.org is accessible"
              parts << "- Try again in a moment"
            elsif error.message.include?("JSON") || error.message.include?("parse")
              parts << "**Data Format Issue:**"
              parts << "- The server returned unexpected data"
              parts << "- This may indicate a server-side problem"
              parts << "- Try a simpler query to isolate the issue"
            else
              parts << "**Troubleshooting:**"
              parts << "- Review the error message above for clues"
              parts << "- Try simplifying your request"
              parts << "- Check the tool documentation for proper usage"
            end

            parts.join("\n")
          end
        end
      end
    end
  end
end

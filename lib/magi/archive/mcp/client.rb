# frozen_string_literal: true

require "http"
require "json"
require_relative "config"
require_relative "auth"

module Magi
  module Archive
    module Mcp
      # HTTP client for Magi Archive Decko API
      #
      # Provides authenticated HTTP access to the Decko MCP API with:
      # - Automatic JWT token management
      # - Role-based access enforcement
      # - Pagination support
      # - Error handling
      #
      # @example Basic usage
      #   client = Magi::Archive::Mcp::Client.new
      #   cards = client.get("/cards", limit: 10)
      #   card = client.get("/cards/User")
      #
      # @example Creating a card
      #   client = Magi::Archive::Mcp::Client.new
      #   client.post("/cards", name: "My Card", content: "Card content")
      class Client
        # API error raised when requests fail
        class APIError < StandardError
          attr_reader :status, :error_code, :details

          def initialize(message, status: nil, error_code: nil, details: nil)
            super(message)
            @status = status
            @error_code = error_code
            @details = details
          end
        end

        # Validation error (4xx responses)
        class ValidationError < APIError; end

        # Authentication error (401 responses)
        class AuthenticationError < APIError; end

        # Authorization error (403 responses)
        class AuthorizationError < APIError; end

        # Not found error (404 responses)
        class NotFoundError < APIError; end

        # Server error (5xx responses)
        class ServerError < APIError; end

        attr_reader :config, :auth

        # Initialize client with optional configuration
        #
        # @param config [Config, nil] optional config object (creates new one if nil)
        def initialize(config = nil)
          @config = config || Config.new
          @auth = Auth.new(@config)
        end

        # GET request to API endpoint
        #
        # @param path [String] the endpoint path
        # @param params [Hash] query parameters
        # @return [Hash, Array] the response data
        # @raise [APIError] if request fails
        def get(path, **params)
          request(:get, path, params: params)
        end

        # POST request to API endpoint
        #
        # @param path [String] the endpoint path
        # @param data [Hash] request body data
        # @return [Hash, Array] the response data
        # @raise [APIError] if request fails
        def post(path, **data)
          request(:post, path, json: data)
        end

        # PATCH request to API endpoint
        #
        # @param path [String] the endpoint path
        # @param data [Hash] request body data
        # @return [Hash, Array] the response data
        # @raise [APIError] if request fails
        def patch(path, **data)
          request(:patch, path, json: data)
        end

        # DELETE request to API endpoint
        #
        # @param path [String] the endpoint path
        # @return [Hash, Array] the response data
        # @raise [APIError] if request fails
        def delete(path)
          request(:delete, path)
        end

        # Health check - check if wiki is operational
        #
        # This is a lightweight endpoint that doesn't require authentication.
        # Checks database connectivity and basic card access.
        #
        # @return [Hash] health status with timestamp and component checks
        # @raise [APIError] if wiki is unreachable
        #
        # @example
        #   client.health_check
        #   # => { "status" => "healthy", "timestamp" => "2025-12-07T...", "checks" => {...} }
        def health_check
          url = config.url_for("/health")
          response = HTTP.get(url)

          unless response.status.success?
            raise APIError.new("Health check failed", status: response.code)
          end

          JSON.parse(response.body.to_s)
        end

        # Ping - ultra-lightweight check
        #
        # Even faster than health_check - just verifies the server responds.
        # Doesn't check database or card access.
        #
        # @return [Hash] ping response with timestamp
        # @raise [APIError] if server doesn't respond
        #
        # @example
        #   client.ping
        #   # => { "status" => "ok", "timestamp" => "2025-12-07T..." }
        def ping
          url = config.url_for("/health/ping")
          response = HTTP.get(url)

          unless response.status.success?
            raise APIError.new("Ping failed", status: response.code)
          end

          JSON.parse(response.body.to_s)
        end

        # GET request returning raw HTTP response (for file downloads)
        #
        # @param path [String] the endpoint path
        # @param params [Hash] query parameters
        # @return [HTTP::Response] the raw HTTP response
        # @raise [APIError] if request fails
        def get_raw(path, **params)
          url = config.url_for(path)
          token = auth.token

          headers = {
            "Authorization" => "Bearer #{token}"
          }

          response = HTTP.headers(headers).get(url, params: params)

          # Check for errors but return raw response
          case response.code
          when 200..299
            response
          when 400..499
            handle_client_error(response)
          when 500..599
            handle_server_error(response)
          else
            raise APIError, "Unexpected HTTP status: #{response.code}"
          end
        rescue HTTP::Error => e
          raise APIError, "HTTP request failed: #{e.message}"
        end

        # Make paginated GET request
        #
        # @param path [String] the endpoint path
        # @param limit [Integer] items per page (default: 50, max: 100)
        # @param offset [Integer] starting offset
        # @param params [Hash] additional query parameters
        # @return [Hash] response with :data, :total, :limit, :offset, :next_offset
        def paginated_get(path, limit: 50, offset: 0, **params)
          params[:limit] = [limit, 100].min
          params[:offset] = offset

          response = get(path, **params)

          {
            data: response["cards"] || response["types"] || response,
            total: response["total"],
            limit: response["limit"] || limit,
            offset: response["offset"] || offset,
            next_offset: response["next_offset"]
          }
        end

        # Fetch all pages of a paginated resource
        #
        # @param path [String] the endpoint path
        # @param limit [Integer] items per page
        # @param params [Hash] additional query parameters
        # @yield [Array] each page of items
        # @return [Array] all items if no block given
        def each_page(path, limit: 50, **params)
          return enum_for(:each_page, path, limit: limit, **params) unless block_given?

          offset = 0
          loop do
            page = paginated_get(path, limit: limit, offset: offset, **params)
            items = page[:data]

            break if items.nil? || items.empty?

            yield items

            # Check if there are more pages
            break unless page[:next_offset]

            offset = page[:next_offset]
          end
        end

        # Fetch all items from a paginated resource
        #
        # @param path [String] the endpoint path
        # @param limit [Integer] items per page
        # @param params [Hash] additional query parameters
        # @return [Array] all items
        def fetch_all(path, limit: 50, **params)
          items = []
          each_page(path, limit: limit, **params) do |page|
            items.concat(page)
          end
          items
        end

        private

        # Make HTTP request with authentication
        def request(method, path, params: nil, json: nil)
          url = config.url_for(path)
          token = auth.token

          headers = {
            "Authorization" => "Bearer #{token}",
            "Content-Type" => "application/json"
          }

          response = case method
                     when :get
                       HTTP.headers(headers).get(url, params: params)
                     when :post
                       HTTP.headers(headers).post(url, json: json)
                     when :patch
                       HTTP.headers(headers).patch(url, json: json)
                     when :delete
                       HTTP.headers(headers).delete(url)
                     else
                       raise ArgumentError, "Unsupported HTTP method: #{method}"
                     end

          handle_response(response)
        rescue HTTP::Error => e
          raise APIError, "HTTP request failed: #{e.message}"
        end

        # Handle HTTP response and errors
        def handle_response(response)
          case response.code
          when 200..299
            parse_response_body(response)
          when 400..499
            handle_client_error(response)
          when 500..599
            handle_server_error(response)
          else
            raise APIError, "Unexpected HTTP status: #{response.code}"
          end
        end

        # Parse response body as JSON
        def parse_response_body(response)
          return nil if response.body.to_s.empty?

          JSON.parse(response.body.to_s)
        rescue JSON::ParserError => e
          raise APIError, "Response parse failed: #{e.message}"
        end

        # Handle 4xx client errors
        def handle_client_error(response)
          data = parse_error_body(response)
          message = data["message"] || data["error"] || "Request failed"
          error_code = data["error"]
          details = data["details"]

          error_class = case response.code
                        when 401
                          AuthenticationError
                        when 403
                          AuthorizationError
                        when 404
                          NotFoundError
                        when 422
                          ValidationError
                        else
                          APIError
                        end

          raise error_class.new(
            message,
            status: response.code,
            error_code: error_code,
            details: details
          )
        end

        # Handle 5xx server errors
        def handle_server_error(response)
          data = parse_error_body(response)
          message = data["message"] || data["error"] || "Server error"

          raise ServerError.new(
            message,
            status: response.code,
            error_code: data["error"]
          )
        end

        # Parse error response body
        def parse_error_body(response)
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          { "error" => "unknown", "message" => response.body.to_s }
        end
      end
    end
  end
end

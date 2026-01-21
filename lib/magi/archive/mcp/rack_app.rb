# frozen_string_literal: true

require 'json'
require 'rack'
require 'securerandom'

module Magi
  module Archive
    module Mcp
      # Simple host authorization middleware - only allows specific hosts
      class HostAuthorization
        ALLOWED_HOSTS = [
          '127.0.0.1',
          '127.0.0.1:3002',
          'localhost',
          'localhost:3002',
          'mcp.magi-agi.org',
          'magi-archive-mcp-proxy.lake-watkins.workers.dev'
        ].freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          host = env['HTTP_HOST'] || env['SERVER_NAME']

          if ALLOWED_HOSTS.include?(host)
            @app.call(env)
          else
            [403, { 'Content-Type' => 'text/plain' }, ["Forbidden: Host '#{host}' not allowed"]]
          end
        end
      end

      # Simple session manager for MCP protocol
      class SessionManager
        def initialize
          @sessions = {}
          @mutex = Mutex.new
        end

        def get_or_create(session_id = nil)
          @mutex.synchronize do
            if session_id && @sessions.key?(session_id)
              session_id
            else
              new_id = SecureRandom.uuid
              @sessions[new_id] = { created_at: Time.now }
              new_id
            end
          end
        end

        def exists?(session_id)
          @mutex.synchronize { @sessions.key?(session_id) }
        end

        def delete(session_id)
          @mutex.synchronize { @sessions.delete(session_id) }
        end
      end

      # SSE Streamer for MCP protocol
      # Supports both old SSE transport (session_id in URL) and new Streamable HTTP (header)
      class SSEStreamer
        def initialize(session_id)
          @session_id = session_id
        end

        def each
          # Send initial endpoint event with session_id in URL
          # This is the OLD SSE transport format that ChatGPT expects
          # Format: /messages?session_id={uuid}
          yield "event: endpoint\n"
          yield "data: /messages?session_id=#{@session_id}\n\n"

          # Keep connection alive with periodic keepalive messages
          # MCP SSE spec recommends 15 second intervals
          begin
            loop do
              sleep 15
              yield ": keepalive #{Time.now.iso8601}\n\n"
            end
          rescue IOError, Errno::EPIPE
            # Client disconnected
          end
        end
      end

      # Pure Rack app without Sinatra - complete control over middleware
      class RackApp
        class << self
          attr_accessor :mcp_server_instance

          def session_manager
            @session_manager ||= SessionManager.new
          end
        end

        # Add MCP protocol headers to response
        def add_mcp_headers(headers, session_id)
          headers.merge({
            'MCP-Protocol-Version' => '2025-06-18',
            'Mcp-Session-Id' => session_id
          })
        end

        def call(env)
          request = Rack::Request.new(env)

          # Extract session ID from request or create new one
          incoming_session_id = env['HTTP_MCP_SESSION_ID']
          session_id = self.class.session_manager.get_or_create(incoming_session_id)

          case [request.request_method, request.path]
          when ['GET', '/health']
            headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
            [200, headers, [JSON.generate({
              status: 'healthy',
              version: Magi::Archive::Mcp::VERSION,
              timestamp: Time.now.iso8601
            })]]

          when ['GET', '/debug-headers']
            headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
            [200, headers, [JSON.generate({
              http_host: env['HTTP_HOST'],
              server_name: env['SERVER_NAME'],
              server_port: env['SERVER_PORT'],
              http_x_forwarded_host: env['HTTP_X_FORWARDED_HOST'],
              http_mcp_session_id: env['HTTP_MCP_SESSION_ID'],
              http_mcp_protocol_version: env['HTTP_MCP_PROTOCOL_VERSION'],
              all_http_headers: env.select { |k,v| k.start_with?('HTTP_') }
            })]]

          when ['GET', '/sse'], ['GET', '/sse/']
            # SSE endpoint - uses Rack hijack API for streaming
            # Handle both /sse and /sse/ for compatibility with different MCP clients
            headers = add_mcp_headers({
              'Content-Type' => 'text/event-stream',
              'Cache-Control' => 'no-cache',
              'X-Accel-Buffering' => 'no' # Disable nginx buffering
            }, session_id)

            # Return async response with session_id for endpoint event
            [200, headers, SSEStreamer.new(session_id)]

          when ['GET', '/.well-known/oauth-authorization-server']
            # Minimal OAuth discovery for Claude.ai compatibility
            # Returns valid structure but signals no actual auth required
            headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
            [200, headers, [JSON.generate({
              issuer: 'https://mcp.magi-agi.org',
              registration_endpoint: 'https://mcp.magi-agi.org/register',
              token_endpoint: 'https://mcp.magi-agi.org/token',
              grant_types_supported: ['client_credentials'],
              response_types_supported: ['token'],
              token_endpoint_auth_methods_supported: ['none']
            })]]

          when ['POST', '/register']
            # Dynamic Client Registration - return static public client
            # This satisfies Claude's DCR requirement without enforcing auth
            headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
            [201, headers, [JSON.generate({
              client_id: 'public-client',
              client_id_issued_at: Time.now.to_i,
              grant_types: ['client_credentials'],
              token_endpoint_auth_method: 'none'
            })]]

          when ['POST', '/token']
            # Token endpoint - return dummy token for authless flow
            headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
            [200, headers, [JSON.generate({
              access_token: 'public-access',
              token_type: 'Bearer',
              expires_in: 31536000  # 1 year - effectively permanent for authless
            })]]

          when ['POST', '/'], ['POST', '/sse'], ['POST', '/sse/'], ['POST', '/message'], ['POST', '/messages']
            # Handle MCP messages on multiple endpoints for compatibility:
            # - /sse, /sse/ : Original endpoints
            # - /message : Streamable HTTP style
            # - /messages : Old SSE transport style (with session_id query param)

            # For /messages endpoint, extract session_id from query param (old SSE transport)
            if request.path == '/messages' || request.path.start_with?('/messages?')
              query_session_id = request.params['session_id']
              if query_session_id && self.class.session_manager.exists?(query_session_id)
                session_id = query_session_id
              elsif query_session_id
                # Session ID provided but not found - return 404 per SSE spec
                headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
                return [404, headers, [JSON.generate({
                  jsonrpc: '2.0',
                  id: nil,
                  error: { code: -32001, message: 'Session not found', data: { session_id: query_session_id } }
                })]]
              end
            end

            begin
              body = request.body.read
              request_data = JSON.parse(body, symbolize_names: true)

              # Use the public handle method which properly initializes instrumentation
              response = self.class.mcp_server_instance.handle(request_data)

              headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
              # Return 202 Accepted for /messages (old SSE transport expects this)
              status_code = (request.path == '/messages' || request.path.start_with?('/messages?')) ? 202 : 200
              [status_code, headers, [JSON.generate(response)]]
            rescue JSON::ParserError => e
              error_response = {
                jsonrpc: '2.0',
                id: nil,
                error: { code: -32700, message: 'Parse error', data: e.message }
              }
              headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
              [400, headers, [JSON.generate(error_response)]]
            rescue StandardError => e
              error_response = {
                jsonrpc: '2.0',
                id: request_data&.dig(:id),
                error: { code: -32603, message: 'Internal error', data: e.message }
              }
              headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
              [500, headers, [JSON.generate(error_response)]]
            end

          when ['DELETE', '/sse'], ['DELETE', '/sse/']
            # Session termination endpoint per MCP spec
            if incoming_session_id
              self.class.session_manager.delete(incoming_session_id)
            end
            headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
            [200, headers, [JSON.generate({ status: 'session closed' })]]

          when ['GET', '/']
            # Per MCP Streamable HTTP spec: check Accept header
            # Return SSE stream if Accept: text/event-stream, else return JSON metadata
            accept_header = env['HTTP_ACCEPT'] || ''

            if accept_header.include?('text/event-stream')
              # Return SSE stream for MCP clients with session_id for endpoint event
              headers = add_mcp_headers({
                'Content-Type' => 'text/event-stream',
                'Cache-Control' => 'no-cache',
                'X-Accel-Buffering' => 'no'
              }, session_id)
              [200, headers, SSEStreamer.new(session_id)]
            else
              # Return JSON metadata for browsers/discovery
              headers = add_mcp_headers({ 'Content-Type' => 'application/json' }, session_id)
              [200, headers, [JSON.generate({
                name: 'magi-archive-mcp',
                version: Magi::Archive::Mcp::VERSION,
                protocol: 'mcp',
                protocol_version: '2025-03-26',
                transport: 'streamable-http',
                transports_supported: ['streamable-http', 'sse'],
                endpoints: {
                  health: '/health',
                  sse: '/sse',
                  messages: '/messages',  # Old SSE transport (ChatGPT)
                  message: '/message'     # Streamable HTTP
                },
                tools_count: self.class.mcp_server_instance.tools.length
              })]]
            end

          else
            headers = add_mcp_headers({ 'Content-Type' => 'text/plain' }, session_id)
            [404, headers, ['Not Found']]
          end
        end
      end
    end
  end
end

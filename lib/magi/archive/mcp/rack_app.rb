# frozen_string_literal: true

require 'json'
require 'rack'

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
          'mcp.magi-agi.org'
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
      # SSE Streamer for MCP protocol
      class SSEStreamer
        def each
          # Send initial endpoint event
          # ChatGPT POSTs to the same /sse URL, so advertise that
          yield "event: endpoint\n"
          yield "data: /sse\n\n"

          # Keep connection alive with periodic keepalive messages
          # In production, this would be managed by the client disconnecting
          # For now, send keepalives every 30 seconds
          begin
            loop do
              sleep 30
              yield ": keepalive\n\n"
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
        end

        def call(env)
          request = Rack::Request.new(env)

          case [request.request_method, request.path]
          when ['GET', '/health']
            [200, { 'Content-Type' => 'application/json' }, [JSON.generate({
              status: 'healthy',
              version: Magi::Archive::Mcp::VERSION,
              timestamp: Time.now.iso8601
            })]]

          when ['GET', '/debug-headers']
            [200, { 'Content-Type' => 'application/json' }, [JSON.generate({
              http_host: env['HTTP_HOST'],
              server_name: env['SERVER_NAME'],
              server_port: env['SERVER_PORT'],
              http_x_forwarded_host: env['HTTP_X_FORWARDED_HOST'],
              all_http_headers: env.select { |k,v| k.start_with?('HTTP_') }
            })]]

          when ['GET', '/sse'], ['GET', '/sse/']
            # SSE endpoint - uses Rack hijack API for streaming
            # Handle both /sse and /sse/ for compatibility with different MCP clients
            headers = {
              'Content-Type' => 'text/event-stream',
              'Cache-Control' => 'no-cache',
              'X-Accel-Buffering' => 'no' # Disable nginx buffering
            }

            # Return async response that will be hijacked by Puma
            [200, headers, SSEStreamer.new]

          when ['POST', '/sse'], ['POST', '/sse/'], ['POST', '/message']
            # Handle MCP messages on /sse, /sse/, and /message endpoints
            # ChatGPT posts to /sse or /sse/, other clients may use /message
            begin
              body = request.body.read
              request_data = JSON.parse(body, symbolize_names: true)

              # Use the public handle method which properly initializes instrumentation
              response = self.class.mcp_server_instance.handle(request_data)

              [200, { 'Content-Type' => 'application/json' }, [JSON.generate(response)]]
            rescue JSON::ParserError => e
              error_response = {
                jsonrpc: '2.0',
                id: nil,
                error: { code: -32700, message: 'Parse error', data: e.message }
              }
              [400, { 'Content-Type' => 'application/json' }, [JSON.generate(error_response)]]
            rescue StandardError => e
              error_response = {
                jsonrpc: '2.0',
                id: request_data&.dig(:id),
                error: { code: -32603, message: 'Internal error', data: e.message }
              }
              [500, { 'Content-Type' => 'application/json' }, [JSON.generate(error_response)]]
            end


          when ['GET', '/']
            [200, { 'Content-Type' => 'application/json' }, [JSON.generate({
              name: 'magi-archive-mcp',
              version: Magi::Archive::Mcp::VERSION,
              protocol: 'mcp',
              transport: 'http/sse',
              endpoints: {
                health: '/health',
                sse: '/sse',
                message: '/message'
              },
              tools_count: self.class.mcp_server_instance.tools.length
            })]]

          else
            [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
          end
        end
      end
    end
  end
end

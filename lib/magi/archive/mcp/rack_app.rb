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
          yield "event: endpoint\n"
          yield "data: /message\n\n"

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

          when ['GET', '/sse']
            # SSE endpoint - uses Rack hijack API for streaming
            headers = {
              'Content-Type' => 'text/event-stream',
              'Cache-Control' => 'no-cache',
              'X-Accel-Buffering' => 'no' # Disable nginx buffering
            }

            # Return async response that will be hijacked by Puma
            [200, headers, SSEStreamer.new]

          when ['POST', '/sse'], ['POST', '/message']
            # Handle MCP messages on both /sse and /message endpoints
            # ChatGPT posts to /sse, other clients may use /message
            begin
              body = request.body.read
              request_data = JSON.parse(body)

              # Route MCP protocol methods to the appropriate handlers
              # mcp gem 0.4.0 made handle_request private, so we route directly
              method = request_data['method']

              result = case method
              when 'initialize'
                self.class.mcp_server_instance.send(:init, request_data)
              when 'tools/list'
                self.class.mcp_server_instance.send(:list_tools, request_data)
              when 'tools/call'
                self.class.mcp_server_instance.send(:call_tool, request_data)
              when 'resources/list'
                self.class.mcp_server_instance.send(:list_resources, request_data)
              when 'resources/read'
                self.class.mcp_server_instance.send(:read_resource_no_content, request_data)
              when 'prompts/list'
                self.class.mcp_server_instance.send(:list_prompts, request_data)
              when 'prompts/get'
                self.class.mcp_server_instance.send(:get_prompt, request_data)
              when 'ping'
                {}
              else
                nil
              end

              # Wrap result in JSON-RPC envelope
              response = if result.nil?
                { jsonrpc: '2.0', id: request_data['id'], error: { code: -32601, message: "Method not found: #{method}" } }
              else
                { jsonrpc: '2.0', id: request_data['id'], result: result }
              end

              [200, { 'Content-Type' => 'application/json' }, [JSON.generate(response)]]
            rescue JSON::ParserError => e
              [400, { 'Content-Type' => 'application/json' }, [JSON.generate({
                error: 'Invalid JSON',
                message: e.message
              })]]
            rescue StandardError => e
              [500, { 'Content-Type' => 'application/json' }, [JSON.generate({
                error: 'Server error',
                message: e.message,
                backtrace: e.backtrace.first(5)
              })]]
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

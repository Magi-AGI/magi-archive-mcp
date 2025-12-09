# config.ru - Rack configuration for MCP HTTP server
require_relative 'bin/mcp-server-http'

# Explicitly run the app WITHOUT Rack::Protection
run MagiArchiveMcpApp

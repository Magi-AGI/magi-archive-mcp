#!/bin/bash
# MCP Server Wrapper - ensures rbenv is loaded for non-interactive SSH sessions

# Source rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# Change to the MCP server directory
cd /home/ubuntu/magi-archive-mcp

# Load environment variables
set -a
source .env
set +a

# Run the MCP server with all arguments passed through
exec bundle exec ruby bin/mcp-server "$@"

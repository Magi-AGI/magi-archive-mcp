#!/usr/bin/env node

import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Path to the Ruby MCP server
const serverPath = join(__dirname, 'mcp-server');
const gemRoot = join(__dirname, '..');

// Get working directory argument (optional)
const workingDir = process.argv[2] || process.cwd();

// Environment variables required for the server
const env = {
  ...process.env,
  DECKO_API_BASE_URL: process.env.DECKO_API_BASE_URL || 'https://wiki.magi-agi.org/api/mcp',
  BUNDLE_GEMFILE: join(gemRoot, 'Gemfile')
};

// Verify authentication credentials are provided
if (!env.MCP_USERNAME && !env.MCP_API_KEY) {
  console.error('❌ Authentication required!');
  console.error('   Set either:');
  console.error('   - MCP_USERNAME and MCP_PASSWORD');
  console.error('   - MCP_API_KEY and MCP_ROLE');
  process.exit(1);
}

// Launch the Ruby MCP server
const ruby = spawn('ruby', [serverPath, workingDir], {
  env,
  stdio: 'inherit'
});

// Handle exit
ruby.on('exit', (code) => {
  process.exit(code || 0);
});

// Handle errors
ruby.on('error', (err) => {
  console.error('❌ Failed to start MCP server:', err.message);
  console.error('   Ensure Ruby is installed and available in PATH');
  process.exit(1);
});

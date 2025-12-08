# frozen_string_literal: true

# Integration test helpers for magi-archive-mcp

module IntegrationHelpers
  # Set up environment for integration tests
  def setup_integration_environment
    # Load production environment if it exists
    prod_env_file = File.join(__dir__, "../../.env.production")
    if File.exist?(prod_env_file)
      require "dotenv"
      Dotenv.load(prod_env_file)
    end

    ENV["INTEGRATION_TEST"] = "true"

    # Use Card-based API key authentication (not username/password)
    # Remove username/password if set from .env file
    ENV.delete("MCP_USERNAME")
    ENV.delete("MCP_PASSWORD")

    # Ensure required env vars are set
    unless ENV["MCP_API_KEY"] && ENV["MCP_ROLE"] && ENV["DECKO_API_BASE_URL"]
      raise "Missing integration test env vars. Set MCP_API_KEY, MCP_ROLE, and DECKO_API_BASE_URL in .env.production"
    end
  end

  # Clean up integration test environment
  def teardown_integration_environment
    # Don't delete INTEGRATION_TEST as it's a flag for all tests
    # Only clean up credentials and server config
    ENV.delete("DECKO_API_BASE_URL")
    ENV.delete("MCP_API_KEY")
    ENV.delete("MCP_ROLE")
  end

  # Get a configured client for integration tests
  def integration_client(role: "admin")
    # Set the role for this client
    ENV["MCP_ROLE"] = role

    # Create and return client (will use MCP_API_KEY from environment)
    Magi::Archive::Mcp::Client.new
  end

  # Wait for server to be ready
  def wait_for_server(timeout: 30)
    require "http"

    url = ENV["DECKO_API_BASE_URL"] || "https://wiki.magi-agi.org/api/mcp"
    start_time = Time.now

    loop do
      begin
        response = HTTP.timeout(2).get("#{url}/health")
        return true if response.status == 200
      rescue StandardError
        # Server not ready yet
      end

      if Time.now - start_time > timeout
        raise "Server at #{url} did not become ready within #{timeout} seconds"
      end

      sleep 1
    end
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, :integration

  # Use around hook to completely disable WebMock for integration tests
  config.around(:each, :integration) do |example|
    # Skip if integration tests disabled
    if ENV["INTEGRATION_TEST"]
      setup_integration_environment

      # Save current WebMock state and disable it completely
      WebMock.allow_net_connect!

      wait_for_server

      # Run the actual test
      example.run

      teardown_integration_environment

      # Restore WebMock restrictions
      WebMock.disable_net_connect!(allow_localhost: false)
    else
      skip "Integration tests disabled (set INTEGRATION_TEST=true to enable)"
    end
  end
end

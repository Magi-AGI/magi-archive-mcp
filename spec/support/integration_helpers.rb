# frozen_string_literal: true

# Integration test helpers for magi-archive-mcp

module IntegrationHelpers
  # Set up environment for integration tests
  def setup_integration_environment
    ENV["INTEGRATION_TEST"] = "true"
    ENV["TEST_API_URL"] ||= "http://localhost:3000/api/mcp"
    ENV["TEST_USERNAME"] ||= "test@example.com"
    ENV["TEST_PASSWORD"] ||= "password123"
  end

  # Clean up integration test environment
  def teardown_integration_environment
    ENV.delete("INTEGRATION_TEST")
    ENV.delete("TEST_API_URL")
    ENV.delete("TEST_USERNAME")
    ENV.delete("TEST_PASSWORD")
  end

  # Generate a test JWT token (requires server running)
  def generate_integration_token(role: "user")
    require "http"

    response = HTTP.post(
      "#{ENV['TEST_API_URL']}/auth",
      json: {
        username: ENV["TEST_USERNAME"],
        password: ENV["TEST_PASSWORD"],
        role: role
      }
    )

    JSON.parse(response.body)["token"]
  end

  # Wait for server to be ready
  def wait_for_server(url: ENV["TEST_API_URL"], timeout: 30)
    require "http"

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

  # Skip integration tests by default unless INTEGRATION_TEST=true
  config.before(:each, :integration) do
    skip "Integration tests disabled (set INTEGRATION_TEST=true to enable)" unless ENV["INTEGRATION_TEST"]

    setup_integration_environment
    wait_for_server
  end

  config.after(:each, :integration) do
    teardown_integration_environment
  end
end

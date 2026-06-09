# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "digest"
require "tmpdir"
require "magi/archive/mcp/tools"

# T8: download_database_backup[_file] verify the server's X-Backup-SHA256 header
# against the bytes they received (and the saved file), and write with binwrite
# so gzip dumps are not corrupted.
RSpec.describe Magi::Archive::Mcp::Tools, "backup checksum verification" do
  let(:config) do
    ENV["MCP_API_KEY"] = "test-api-key"
    ENV["DECKO_API_BASE_URL"] = "https://test.example.com/api/mcp"
    ENV["MCP_ROLE"] = "admin"
    Magi::Archive::Mcp::Config.new
  end
  let(:client) { Magi::Archive::Mcp::Client.new(config) }
  let(:tools) { described_class.new(client) }

  # binary gzip-ish payload
  let(:gz_body) { "\x1f\x8b\x08\x00payload\x00\xFF".dup.force_encoding("ASCII-8BIT") }
  let(:correct_sha) { Digest::SHA256.hexdigest(gz_body) }

  before do
    stub_request(:post, "https://test.example.com/api/mcp/auth")
      .to_return(status: 201,
                 body: { "token" => "test-jwt", "role" => "admin", "expires_in" => 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_backup(sha:)
    stub_request(:get, "https://test.example.com/api/mcp/admin/database/backup")
      .to_return(status: 200, body: gz_body, headers: { "X-Backup-SHA256" => sha })
  end

  context "when the checksum matches" do
    before { stub_backup(sha: correct_sha) }

    it "returns the raw bytes" do
      expect(tools.download_database_backup).to eq(gz_body)
    end

    it "writes the backup binary-safe to save_path" do
      path = File.join(Dir.tmpdir, "t8_#{SecureRandom.hex(4)}.sql.gz")
      begin
        expect(tools.download_database_backup(save_path: path)).to eq(path)
        expect(File.binread(path)).to eq(gz_body)
      ensure
        File.delete(path) if File.exist?(path)
      end
    end
  end

  context "when the checksum does not match" do
    before { stub_backup(sha: "0" * 64) }

    it "raises an APIError instead of silently succeeding" do
      expect { tools.download_database_backup }
        .to raise_error(Magi::Archive::Mcp::Client::APIError, /checksum mismatch/i)
    end
  end

  context "when the server sends no checksum header" do
    before do
      stub_request(:get, "https://test.example.com/api/mcp/admin/database/backup")
        .to_return(status: 200, body: gz_body)
    end

    it "still returns the bytes (header is optional)" do
      expect(tools.download_database_backup).to eq(gz_body)
    end
  end

  describe "#download_database_backup_file" do
    before do
      stub_request(:get, %r{/admin/database/backup/download/.+})
        .to_return(status: 200, body: gz_body, headers: { "X-Backup-SHA256" => correct_sha })
    end

    it "verifies the checksum of an existing backup fetched by filename" do
      expect(tools.download_database_backup_file("magi_archive_backup_20260101_000000.sql.gz"))
        .to eq(gz_body)
    end
  end
end

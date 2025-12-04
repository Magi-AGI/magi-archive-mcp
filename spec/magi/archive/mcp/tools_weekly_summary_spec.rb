# frozen_string_literal: true

require "spec_helper"

RSpec.describe Magi::Archive::Mcp::Tools, "weekly summary" do
  let(:tools) { described_class.new }
  let(:valid_token) { "test-token-123" }
  let(:base_url) { "https://test.example.com" }

  before do
    allow_any_instance_of(Magi::Archive::Mcp::Client).to receive(:base_url).and_return(base_url)
    allow_any_instance_of(Magi::Archive::Mcp::Auth).to receive(:token).and_return(valid_token)
  end

  describe "#get_recent_changes" do
    let(:recent_cards) do
      [
        {
          "name" => "Business Plan+Executive Summary",
          "id" => 123,
          "type" => "Basic",
          "updated_at" => "2025-12-03T10:00:00Z"
        },
        {
          "name" => "Technical Documentation",
          "id" => 124,
          "type" => "Basic",
          "updated_at" => "2025-12-02T15:30:00Z"
        }
      ]
    end

    it "fetches cards updated in the last 7 days by default" do
      stub_request(:get, "#{base_url}/api/mcp/cards")
        .with(
          headers: { "Authorization" => "Bearer #{valid_token}" },
          query: hash_including("updated_since", "updated_before", "limit" => "100", "offset" => "0")
        )
        .to_return(
          status: 200,
          body: {
            cards: recent_cards,
            total: 2,
            offset: 0,
            next_offset: nil
          }.to_json
        )

      result = tools.get_recent_changes

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first["name"]).to eq("Business Plan+Executive Summary")
    end

    it "supports custom date range" do
      stub_request(:get, "#{base_url}/api/mcp/cards")
        .with(
          headers: { "Authorization" => "Bearer #{valid_token}" },
          query: hash_including(
            "updated_since" => "2025-11-25T00:00:00Z",
            "updated_before" => "2025-12-02T00:00:00Z"
          )
        )
        .to_return(
          status: 200,
          body: { cards: recent_cards, total: 2, offset: 0, next_offset: nil }.to_json
        )

      result = tools.get_recent_changes(since: "2025-11-25", before: "2025-12-02")

      expect(result.size).to eq(2)
    end

    it "handles pagination to fetch all results" do
      page1 = { cards: [recent_cards[0]], total: 2, offset: 0, next_offset: 1 }
      page2 = { cards: [recent_cards[1]], total: 2, offset: 1, next_offset: nil }

      stub_request(:get, "#{base_url}/api/mcp/cards")
        .with(query: hash_including("offset" => "0"))
        .to_return(status: 200, body: page1.to_json)

      stub_request(:get, "#{base_url}/api/mcp/cards")
        .with(query: hash_including("offset" => "1"))
        .to_return(status: 200, body: page2.to_json)

      result = tools.get_recent_changes

      expect(result.size).to eq(2)
    end

    it "sorts results by updated_at descending" do
      stub_request(:get, "#{base_url}/api/mcp/cards")
        .to_return(
          status: 200,
          body: { cards: recent_cards.reverse, total: 2, offset: 0, next_offset: nil }.to_json
        )

      result = tools.get_recent_changes

      expect(result.first["updated_at"]).to eq("2025-12-03T10:00:00Z")
      expect(result.last["updated_at"]).to eq("2025-12-02T15:30:00Z")
    end
  end

  describe "#scan_git_repos" do
    let(:test_repo_path) { File.join(Dir.tmpdir, "test-repo-#{rand(10000)}") }

    before do
      FileUtils.mkdir_p(File.join(test_repo_path, ".git"))
    end

    after do
      FileUtils.rm_rf(test_repo_path) if File.exist?(test_repo_path)
    end

    it "finds git repositories in the base path" do
      allow(tools).to receive(:get_git_commits).and_return([])

      result = tools.scan_git_repos(base_path: Dir.tmpdir, days: 7)

      expect(result).to be_a(Hash)
    end

    it "excludes repositories with no recent commits" do
      allow(tools).to receive(:find_git_repos).and_return([test_repo_path])
      allow(tools).to receive(:get_git_commits).and_return([])

      result = tools.scan_git_repos(base_path: Dir.tmpdir)

      expect(result).to be_empty
    end

    it "includes repositories with recent commits" do
      commits = [
        { "hash" => "abc123", "author" => "Test User", "date" => "2025-12-03", "subject" => "Test commit" }
      ]

      allow(tools).to receive(:find_git_repos).and_return([test_repo_path])
      allow(tools).to receive(:get_git_commits).and_return(commits)

      result = tools.scan_git_repos(base_path: Dir.tmpdir)

      repo_name = File.basename(test_repo_path)
      expect(result[repo_name]).to eq(commits)
    end
  end

  describe "#format_weekly_summary" do
    let(:card_changes) do
      [
        { "name" => "Business Plan+Executive Summary", "updated_at" => "2025-12-03T10:00:00Z" },
        { "name" => "Business Plan+Vision", "updated_at" => "2025-12-02T15:30:00Z" },
        { "name" => "Technical Documentation", "updated_at" => "2025-12-01T12:00:00Z" }
      ]
    end

    let(:repo_changes) do
      {
        "magi-archive" => [
          { "hash" => "abc123", "author" => "Dev", "date" => "2025-12-03", "subject" => "Add feature" }
        ],
        "magi-archive-mcp" => [
          { "hash" => "def456", "author" => "Dev", "date" => "2025-12-02", "subject" => "Fix bug" }
        ]
      }
    end

    it "generates markdown with title and executive summary" do
      result = tools.format_weekly_summary(card_changes, repo_changes)

      expect(result).to include("# Weekly Work Summary")
      expect(result).to include("## Executive Summary")
    end

    it "includes wiki card updates section" do
      result = tools.format_weekly_summary(card_changes, repo_changes)

      expect(result).to include("## Wiki Card Updates")
      expect(result).to include("`Business Plan+Executive Summary`")
      expect(result).to include("`Technical Documentation`")
    end

    it "groups card updates by parent" do
      result = tools.format_weekly_summary(card_changes, repo_changes)

      expect(result).to include("### Business Plan")
    end

    it "includes repository changes section" do
      result = tools.format_weekly_summary(card_changes, repo_changes)

      expect(result).to include("## Repository & Code Changes")
      expect(result).to include("### magi-archive")
      expect(result).to include("### magi-archive-mcp")
      expect(result).to include("`abc123` Add feature")
      expect(result).to include("`def456` Fix bug")
    end

    it "includes next steps section" do
      result = tools.format_weekly_summary(card_changes, repo_changes)

      expect(result).to include("## Next Steps")
    end

    it "supports custom title" do
      result = tools.format_weekly_summary(
        card_changes,
        repo_changes,
        title: "Custom Weekly Summary 2025 12 09"
      )

      expect(result).to include("# Custom Weekly Summary 2025 12 09")
    end

    it "supports custom executive summary" do
      custom_summary = "This week focused on MCP API enhancements and documentation."
      result = tools.format_weekly_summary(
        card_changes,
        repo_changes,
        executive_summary: custom_summary
      )

      expect(result).to include(custom_summary)
    end

    it "handles empty card changes" do
      result = tools.format_weekly_summary([], repo_changes)

      expect(result).not_to include("## Wiki Card Updates")
      expect(result).to include("## Repository & Code Changes")
    end

    it "handles empty repository changes" do
      result = tools.format_weekly_summary(card_changes, {})

      expect(result).to include("## Wiki Card Updates")
      expect(result).not_to include("## Repository & Code Changes")
    end
  end

  describe "#create_weekly_summary" do
    let(:card_changes) do
      [{ "name" => "Test Card", "updated_at" => "2025-12-03T10:00:00Z" }]
    end

    let(:repo_changes) do
      { "test-repo" => [{ "hash" => "abc", "author" => "Dev", "date" => "2025-12-03", "subject" => "Test" }] }
    end

    before do
      allow(tools).to receive(:get_recent_changes).and_return(card_changes)
      allow(tools).to receive(:scan_git_repos).and_return(repo_changes)
    end

    it "returns markdown content when create_card is false" do
      result = tools.create_weekly_summary(create_card: false)

      expect(result).to be_a(String)
      expect(result).to include("# Weekly Work Summary")
      expect(result).to include("## Executive Summary")
    end

    it "creates a weekly summary card" do
      stub_request(:post, "#{base_url}/api/mcp/cards")
        .with(
          headers: { "Authorization" => "Bearer #{valid_token}" },
          body: hash_including(
            "name" => /Weekly Work Summary \d{4} \d{2} \d{2}/,
            "type" => "Basic"
          )
        )
        .to_return(
          status: 201,
          body: {
            name: "Weekly Work Summary 2025 12 03",
            id: 999,
            type: "Basic",
            content: "Summary content"
          }.to_json
        )

      result = tools.create_weekly_summary

      expect(result).to be_a(Hash)
      expect(result["name"]).to match(/Weekly Work Summary/)
    end

    it "supports custom date" do
      stub_request(:post, "#{base_url}/api/mcp/cards")
        .with(body: hash_including("name" => "Weekly Work Summary 2025 12 09"))
        .to_return(
          status: 201,
          body: { name: "Weekly Work Summary 2025 12 09", id: 999, type: "Basic" }.to_json
        )

      result = tools.create_weekly_summary(date: "2025 12 09")

      expect(result["name"]).to eq("Weekly Work Summary 2025 12 09")
    end

    it "supports custom executive summary" do
      custom_summary = "Focused on Phase 2.1 completion."

      stub_request(:post, "#{base_url}/api/mcp/cards")
        .with(body: hash_including("content" => /Focused on Phase 2\.1 completion/))
        .to_return(status: 201, body: { name: "Summary", id: 999, type: "Basic" }.to_json)

      tools.create_weekly_summary(executive_summary: custom_summary)

      expect(WebMock).to have_requested(:post, "#{base_url}/api/mcp/cards")
    end

    it "scans repositories from specified base path" do
      expect(tools).to receive(:scan_git_repos).with(base_path: "/custom/path", days: 7)

      stub_request(:post, "#{base_url}/api/mcp/cards")
        .to_return(status: 201, body: { name: "Summary", id: 999, type: "Basic" }.to_json)

      tools.create_weekly_summary(base_path: "/custom/path")
    end

    it "supports custom lookback period" do
      expect(tools).to receive(:get_recent_changes).with(days: 14)

      stub_request(:post, "#{base_url}/api/mcp/cards")
        .to_return(status: 201, body: { name: "Summary", id: 999, type: "Basic" }.to_json)

      tools.create_weekly_summary(days: 14)
    end
  end

  describe "private helper methods" do
    describe "#parse_time" do
      it "parses string dates" do
        result = tools.send(:parse_time, "2025-12-03")
        expect(result).to be_a(Time)
      end

      it "returns Time objects unchanged" do
        time = Time.now
        result = tools.send(:parse_time, time)
        expect(result).to eq(time)
      end
    end

    describe "#find_git_repos" do
      let(:test_base) { File.join(Dir.tmpdir, "test-base-#{rand(10000)}") }

      before do
        FileUtils.mkdir_p(test_base)
      end

      after do
        FileUtils.rm_rf(test_base) if File.exist?(test_base)
      end

      it "finds git repo in base directory" do
        FileUtils.mkdir_p(File.join(test_base, ".git"))

        result = tools.send(:find_git_repos, test_base)

        expect(result).to include(test_base)
      end

      it "finds git repos in subdirectories" do
        repo1 = File.join(test_base, "repo1")
        repo2 = File.join(test_base, "subdir", "repo2")

        FileUtils.mkdir_p(File.join(repo1, ".git"))
        FileUtils.mkdir_p(File.join(repo2, ".git"))

        result = tools.send(:find_git_repos, test_base)

        expect(result).to include(repo1)
        expect(result).to include(repo2)
      end
    end

    describe "#format_card_changes" do
      let(:cards) do
        [
          { "name" => "Parent+Child1", "updated_at" => "2025-12-03T10:00:00Z" },
          { "name" => "Parent+Child2", "updated_at" => "2025-12-02T15:30:00Z" },
          { "name" => "Standalone", "updated_at" => "2025-12-01T12:00:00Z" }
        ]
      end

      it "groups cards by parent" do
        result = tools.send(:format_card_changes, cards)

        expect(result).to include("### Parent")
        expect(result).to include("`Parent+Child1`")
        expect(result).to include("`Parent+Child2`")
        expect(result).to include("`Standalone`")
      end

      it "includes update dates" do
        result = tools.send(:format_card_changes, cards)

        expect(result).to include("(2025-12-03)")
        expect(result).to include("(2025-12-02)")
      end
    end

    describe "#format_repo_changes" do
      let(:repo_changes) do
        {
          "test-repo" => [
            { "hash" => "abc123", "author" => "Dev1", "date" => "2025-12-03", "subject" => "Add feature" },
            { "hash" => "def456", "author" => "Dev2", "date" => "2025-12-02", "subject" => "Fix bug" }
          ]
        }
      end

      it "formats repository sections" do
        result = tools.send(:format_repo_changes, repo_changes)

        expect(result).to include("### test-repo")
        expect(result).to include("**2 commits**")
      end

      it "lists commits with details" do
        result = tools.send(:format_repo_changes, repo_changes)

        expect(result).to include("`abc123` Add feature (Dev1, 2025-12-03)")
        expect(result).to include("`def456` Fix bug (Dev2, 2025-12-02)")
      end

      it "limits commit list to 10 with overflow message" do
        many_commits = (1..15).map do |i|
          { "hash" => "hash#{i}", "author" => "Dev", "date" => "2025-12-03", "subject" => "Commit #{i}" }
        end

        result = tools.send(:format_repo_changes, { "test-repo" => many_commits })

        expect(result).to include("... and 5 more commits")
      end
    end

    describe "#format_date" do
      it "formats ISO8601 dates" do
        result = tools.send(:format_date, "2025-12-03T10:00:00Z")
        expect(result).to eq("2025-12-03")
      end

      it "returns original string on parse failure" do
        result = tools.send(:format_date, "invalid-date")
        expect(result).to eq("invalid-date")
      end
    end
  end
end

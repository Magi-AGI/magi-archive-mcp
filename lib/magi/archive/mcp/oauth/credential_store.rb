# frozen_string_literal: true

require "securerandom"

module Magi
  module Archive
    module Mcp
      module OAuth
        # Thread-safe in-memory cache of per-user Tools instances
        #
        # Maps session IDs (from JWT jti claims) to authenticated Tools
        # instances. Each user who authenticates via OAuth gets their own
        # Tools instance backed by their Decko credentials.
        #
        # Also stores refresh tokens and their mappings to sessions.
        class CredentialStore
          # How long unused sessions are kept before cleanup (2 hours)
          SESSION_TTL = 7200

          # How long refresh tokens remain valid (24 hours)
          REFRESH_TOKEN_TTL = 86_400

          def initialize
            @sessions = {}
            @refresh_tokens = {}
            @mutex = Mutex.new
          end

          # Store a session with its Tools instance
          #
          # @param session_id [String] unique session ID (JWT jti)
          # @param username [String] Decko username
          # @param role [String] user role
          # @param tools [Magi::Archive::Mcp::Tools] authenticated Tools instance
          # @return [void]
          def store_session(session_id, username:, role:, tools:)
            @mutex.synchronize do
              @sessions[session_id] = {
                username: username,
                role: role,
                tools: tools,
                created_at: Time.now,
                last_used_at: Time.now
              }
            end
          end

          # Get Tools instance for a session, updating last_used_at
          #
          # @param session_id [String] the session ID
          # @return [Hash, nil] session data with :tools, :username, :role or nil if not found
          def get_session(session_id)
            @mutex.synchronize do
              session = @sessions[session_id]
              return nil unless session

              session[:last_used_at] = Time.now
              session
            end
          end

          # Store a refresh token mapped to a session
          #
          # @param refresh_token [String] the refresh token
          # @param session_id [String] the session ID it maps to
          # @param username [String] Decko username
          # @param password [String] Decko password (for re-auth)
          # @param role [String] user role
          # @return [void]
          def store_refresh_token(refresh_token, session_id:, username:, password:, role:)
            @mutex.synchronize do
              @refresh_tokens[refresh_token] = {
                session_id: session_id,
                username: username,
                password: password,
                role: role,
                created_at: Time.now
              }
            end
          end

          # Look up and consume a refresh token
          #
          # @param refresh_token [String] the refresh token
          # @return [Hash, nil] token data with :session_id, :username, :password, :role or nil
          def consume_refresh_token(refresh_token)
            @mutex.synchronize do
              data = @refresh_tokens.delete(refresh_token)
              return nil unless data
              return nil if Time.now - data[:created_at] > REFRESH_TOKEN_TTL

              data
            end
          end

          # Delete a session and any associated refresh tokens
          #
          # @param session_id [String] the session ID to revoke
          # @return [void]
          def revoke_session(session_id)
            @mutex.synchronize do
              @sessions.delete(session_id)
              @refresh_tokens.reject! { |_, v| v[:session_id] == session_id }
            end
          end

          # Revoke by token value (either access token's jti or refresh token)
          #
          # @param token [String] token to revoke
          # @return [void]
          def revoke_token(token)
            @mutex.synchronize do
              # Try as session_id first
              if @sessions.key?(token)
                @sessions.delete(token)
                @refresh_tokens.reject! { |_, v| v[:session_id] == token }
                return
              end

              # Try as refresh token
              data = @refresh_tokens.delete(token)
              @sessions.delete(data[:session_id]) if data
            end
          end

          # Clean up expired sessions and refresh tokens
          #
          # @return [Integer] number of sessions purged
          def cleanup!
            @mutex.synchronize do
              now = Time.now
              expired_sessions = @sessions.select { |_, v| now - v[:last_used_at] > SESSION_TTL }
              expired_sessions.each_key { |id| @sessions.delete(id) }

              @refresh_tokens.reject! { |_, v| now - v[:created_at] > REFRESH_TOKEN_TTL }

              expired_sessions.size
            end
          end

          # Number of active sessions
          #
          # @return [Integer]
          def session_count
            @mutex.synchronize { @sessions.size }
          end

          # Number of active refresh tokens
          #
          # @return [Integer]
          def refresh_token_count
            @mutex.synchronize { @refresh_tokens.size }
          end
        end
      end
    end
  end
end

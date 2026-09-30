require "digest"
require "securerandom"

module Authentication
  class SessionIssuer
    TOKEN_BYTES = 32
    SESSION_TTL = 24.hours
    Result = Struct.new(:session, :token, keyword_init: true)

    def self.call(user:)
      token = SecureRandom.urlsafe_base64(TOKEN_BYTES, false)
      session = user.auth_sessions.create!(
        token_digest: Digest::SHA256.hexdigest(token),
        expires_at: SESSION_TTL.from_now
      )

      Result.new(session: session, token: token)
    end
  end
end
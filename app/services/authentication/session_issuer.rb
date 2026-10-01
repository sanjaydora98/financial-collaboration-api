require "digest"
require "securerandom"

module Authentication
  class SessionIssuer
    Result = Struct.new(:session, :token, keyword_init: true)

    def self.call(user:)
      token = SecureRandom.urlsafe_base64(AuthConstants::TOKEN_BYTES, false)
      session = user.auth_sessions.create!(
        token_digest: Digest::SHA256.hexdigest(token),
        expires_at: AuthConstants::SESSION_TTL.from_now
      )

      Result.new(session: session, token: token)
    end
  end
end
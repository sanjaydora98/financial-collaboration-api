require "digest"

module Authentication
  class SessionAuthenticator
    def self.call(authorization_header)
      match = authorization_header.to_s.match(AuthConstants::TOKEN_PATTERN)
      return unless match

      session = AuthSession.includes(:user).active.find_by(token_digest: Digest::SHA256.hexdigest(match[1]))
      session if session && session.user.disabled_at.nil?
    end
  end
end
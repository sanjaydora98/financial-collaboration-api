require "securerandom"

module Authentication
  class AuthenticateUser
    DUMMY_PASSWORD_DIGEST = BCrypt::Password.create(
      SecureRandom.hex(32),
      cost: BCrypt::Engine.cost
    ).to_s.freeze

    def self.call(email:, password:)
      normalized_email = email.to_s.strip.downcase
      user = User.find_by(email: normalized_email)

      authenticated_user = if user
        user.authenticate(password.to_s)
      else
        BCrypt::Password.new(DUMMY_PASSWORD_DIGEST).is_password?(password.to_s)
        false
      end

      return unless authenticated_user.is_a?(User) && user.disabled_at.nil?

      [user, SessionIssuer.call(user: user)]
    end
  end
end
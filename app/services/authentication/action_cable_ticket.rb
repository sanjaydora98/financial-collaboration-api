module Authentication
  class ActionCableTicket
    def self.issue(session:)
      verifier.generate(
        { auth_session_id: session.id },
        purpose: AuthConstants::ACTION_CABLE_TICKET_PURPOSE,
        expires_in: AuthConstants::ACTION_CABLE_TICKET_TTL
      )
    end

    def self.authenticate(ticket:)
      payload = verifier.verified(ticket, purpose: AuthConstants::ACTION_CABLE_TICKET_PURPOSE)
      return unless payload.is_a?(Hash) && payload["auth_session_id"].present?

      session = AuthSession.includes(:user).active.find_by(id: payload["auth_session_id"])
      session if session && session.user.disabled_at.nil?
    end

    def self.verifier
      Rails.application.message_verifier(:action_cable_ticket)
    end
    private_class_method :verifier
  end
end
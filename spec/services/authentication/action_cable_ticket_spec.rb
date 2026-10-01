require "rails_helper"

RSpec.describe Authentication::ActionCableTicket do
  it "rejects invalid, expired, revoked, and disabled-user tickets" do
    user = User.create!(email: "cable-ticket-#{SecureRandom.hex(4)}@example.com", name: "Cable", password: "password123")
    session = user.auth_sessions.create!(token_digest: SecureRandom.hex(32), expires_at: 1.hour.from_now)
    ticket = described_class.issue(session: session)

    expect(described_class.authenticate(ticket: "invalid")).to be_nil
    expect(described_class.authenticate(ticket: ticket)).to eq(session)

    session.update!(revoked_at: Time.current)
    expect(described_class.authenticate(ticket: ticket)).to be_nil

    expired_session = user.auth_sessions.create!(token_digest: SecureRandom.hex(32), expires_at: 1.minute.ago)
    expired_ticket = described_class.issue(session: expired_session)
    expect(described_class.authenticate(ticket: expired_ticket)).to be_nil

    disabled_session = user.auth_sessions.create!(token_digest: SecureRandom.hex(32), expires_at: 1.hour.from_now)
    disabled_ticket = described_class.issue(session: disabled_session)
    user.update!(disabled_at: Time.current)
    expect(described_class.authenticate(ticket: disabled_ticket)).to be_nil
  end
end
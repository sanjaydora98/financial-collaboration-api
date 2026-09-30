require "rails_helper"

RSpec.describe Authentication::SessionIssuer do
  it "stores only a SHA-256 digest of a cryptographically random opaque token" do
    user = User.create!(email: "issuer@example.com", name: "Issuer", password: "password123")

    result = described_class.call(user: user)

    expect(result.token).to match(/\A[A-Za-z0-9_-]{43}\z/)
    expect(result.session.token_digest).to eq(Digest::SHA256.hexdigest(result.token))
    expect(result.session.token_digest).not_to eq(result.token)
    expect(AuthSession.exists?(token_digest: result.token)).to be(false)
    expect(result.session.expires_at).to be_within(2.seconds).of(24.hours.from_now)
    expect(result.session.revoked_at).to be_nil
    expect(result.session.last_used_at).to be_nil
  end
end
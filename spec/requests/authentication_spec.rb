require "rails_helper"

RSpec.describe "Authentication API", type: :request do
  def register(email: "person@example.com", name: "Test Person", password: "password123")
    post "/auth/register", params: {
      user: { email: email, name: name, password: password }
    }, as: :json
  end

  def response_json
    JSON.parse(response.body)
  end

  def authenticate(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_user(email: "person@example.com", password: "password123", disabled_at: nil)
    User.create!(email: email, name: "Test Person", password: password, disabled_at: disabled_at)
  end

  def token_for(user, expires_at: 1.hour.from_now, revoked_at: nil)
    token = SecureRandom.urlsafe_base64(32, false)
    session = user.auth_sessions.create!(
      token_digest: Digest::SHA256.hexdigest(token),
      expires_at: expires_at,
      revoked_at: revoked_at
    )
    [token, session]
  end

  describe "POST /auth/register" do
    it "creates a user and returns a one-time bearer token" do
      expect { register }.to change(User, :count).by(1).and change(AuthSession, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response_json.dig("user", "email")).to eq("person@example.com")
      expect(response_json["token"]).to match(/\A[A-Za-z0-9_-]{43}\z/)
      expect(response_json).not_to have_key("password_digest")
      expect(response.body).not_to include("token_digest", "password_digest")
    end

    it "rejects duplicate email case-insensitively" do
      register(email: "person@example.com")
      post "/auth/register", params: {
        user: { email: " PERSON@EXAMPLE.COM ", name: "Duplicate", password: "password123" }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.count).to eq(1)
      expect(AuthSession.count).to eq(1)
    end

    it "returns validation errors for invalid registration input" do
      post "/auth/register", params: { user: { email: "bad", name: "", password: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /auth/login" do
    it "authenticates email and password and issues a bearer token" do
      create_user(email: "person@example.com")

      post "/auth/login", params: { email: " PERSON@example.com ", password: "password123" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response_json.dig("user", "email")).to eq("person@example.com")
      expect(response_json["token"]).to be_present
    end

    it "returns the same unauthorized response for an incorrect password and unknown email" do
      create_user(email: "person@example.com")
      post "/auth/login", params: { email: "person@example.com", password: "wrong-password" }, as: :json
      wrong_password_body = response.body
      expect(response).to have_http_status(:unauthorized)

      post "/auth/login", params: { email: "unknown@example.com", password: "wrong-password" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to eq(wrong_password_body)
    end

    it "returns 422 when required login fields are missing" do
      post "/auth/login", params: { email: "person@example.com" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not issue a session for a disabled user" do
      create_user(email: "disabled@example.com", disabled_at: Time.current)

      expect {
        post "/auth/login", params: { email: "disabled@example.com", password: "password123" }, as: :json
      }.not_to change(AuthSession, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "authenticated endpoints" do
    it "issues a short-lived ActionCable ticket for the authenticated session" do
      user = create_user
      token, session = token_for(user)

      post "/auth/cable_ticket", headers: authenticate(token)

      expect(response).to have_http_status(:ok)
      ticket = response_json.fetch("ticket")
      expect(ticket).to be_present
      expect(Authentication::ActionCableTicket.authenticate(ticket: ticket)).to eq(session)
      expect(response.body).not_to include(token)
    end

    it "returns 401 when the Authorization header is missing or invalid" do
      get "/auth/me"
      expect(response).to have_http_status(:unauthorized)

      get "/auth/me", headers: authenticate("not-a-valid-token")
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects expired, revoked, and disabled-user sessions" do
      expired_user = create_user(email: "expired@example.com")
      expired_token, = token_for(expired_user, expires_at: 1.minute.ago)
      get "/auth/me", headers: authenticate(expired_token)
      expect(response).to have_http_status(:unauthorized)

      revoked_user = create_user(email: "revoked@example.com")
      revoked_token, = token_for(revoked_user, revoked_at: Time.current)
      get "/auth/me", headers: authenticate(revoked_token)
      expect(response).to have_http_status(:unauthorized)

      disabled_user = create_user(email: "disabled-session@example.com", disabled_at: Time.current)
      disabled_token, = token_for(disabled_user)
      get "/auth/me", headers: authenticate(disabled_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns only the current token owner's profile and updates last_used_at" do
      owner = create_user(email: "owner@example.com")
      other_user = create_user(email: "other@example.com")
      token, session = token_for(owner)

      get "/auth/me?user_id=#{other_user.id}", headers: authenticate(token)

      expect(response).to have_http_status(:ok)
      expect(response_json.dig("user", "email")).to eq("owner@example.com")
      expect(response.body).not_to include(other_user.email, "password_digest", "token_digest")
      expect(session.reload.last_used_at).to be_within(2.seconds).of(Time.current)
    end

    it "revokes only the current session on logout" do
      user = create_user
      token, session = token_for(user)

      delete "/auth/logout", headers: authenticate(token)

      expect(response).to have_http_status(:no_content)
      expect(session.reload.revoked_at).to be_present
      get "/auth/me", headers: authenticate(token)
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
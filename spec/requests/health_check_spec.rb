require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "returns success when the application is healthy" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end

  it "allows preflight requests only from the configured frontend origin" do
    options "/auth/me", headers: {
      "Origin" => "http://localhost:3001",
      "Access-Control-Request-Method" => "POST",
      "Access-Control-Request-Headers" => "authorization,content-type"
    }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:3001")
    expect(Rails.application.config.action_cable.allowed_request_origins).to include("http://localhost:3001")

    options "/auth/me", headers: {
      "Origin" => "http://untrusted.example",
      "Access-Control-Request-Method" => "POST"
    }

    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end
end
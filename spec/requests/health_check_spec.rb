require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "returns success when the application is healthy" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end
end
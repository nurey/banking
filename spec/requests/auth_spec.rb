# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth endpoints", type: :request do
  let(:allowed_origin) { ENV["CORS_ORIGINS"] || "http://localhost:3000" }

  describe "POST /registration" do
    it "creates a user and sets a session cookie" do
      post "/registration",
        params: { email_address: "new@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:created)
      expect(response.cookies["session_id"]).to be_present
      body = JSON.parse(response.body)
      expect(body["user"]["email_address"]).to eq("new@example.com")
      expect(body["user"]).not_to have_key("password_digest")
    end

    it "returns 422 for duplicate email" do
      User.create!(email_address: "dupe@example.com", password: "password123")
      post "/registration",
        params: { email_address: "dupe@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end

    it "returns 422 for missing email" do
      post "/registration",
        params: { email_address: "", password: "password123" },
        headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /session" do
    before do
      User.create!(email_address: "user@example.com", password: "password123")
    end

    it "returns a session cookie for valid credentials" do
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:created)
      expect(response.cookies["session_id"]).to be_present
      body = JSON.parse(response.body)
      expect(body["user"]["email_address"]).to eq("user@example.com")
    end

    it "returns 401 for wrong password" do
      post "/session",
        params: { email_address: "user@example.com", password: "wrong" },
        headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for non-existent email" do
      post "/session",
        params: { email_address: "nobody@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /session" do
    it "returns the current user when authenticated" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      get "/session"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["user"]["email_address"]).to eq("user@example.com")
    end

    it "returns 401 when not authenticated" do
      get "/session"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /session" do
    it "invalidates the session" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      delete "/session", headers: { "Origin" => allowed_origin }
      expect(response).to have_http_status(:ok)

      get "/credit_card_transactions"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "Cookie authentication" do
    it "returns 401 when accessing a protected endpoint without a cookie" do
      get "/credit_card_transactions"
      expect(response).to have_http_status(:unauthorized)
    end

    it "allows access after login" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      get "/credit_card_transactions"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "CSRF protection" do
    it "rejects POST requests without an Origin header" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session", params: { email_address: "user@example.com", password: "password123" }

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects POST requests from a foreign origin" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => "https://evil.com" }

      expect(response).to have_http_status(:forbidden)
    end

    it "allows GET requests without an Origin header" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      get "/credit_card_transactions"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Session expiry" do
    it "rejects sessions older than 30 days" do
      user = User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      # Age the session beyond 30 days
      user.sessions.update_all(created_at: 31.days.ago)

      get "/session"
      expect(response).to have_http_status(:unauthorized)
    end

    it "allows sessions within 30 days" do
      User.create!(email_address: "user@example.com", password: "password123")
      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        headers: { "Origin" => allowed_origin }

      get "/session"
      expect(response).to have_http_status(:ok)
    end
  end
end

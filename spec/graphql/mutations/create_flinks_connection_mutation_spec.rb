# frozen_string_literal: true

require "rails_helper"

RSpec.describe "createFlinksConnection mutation" do
  fixtures :users

  let(:current_user) { users(:alice) }

  def execute_graphql(query, variables: {})
    super(query, variables: variables, context: { current_user: current_user })
  end

  let(:mutation) do
    <<~GQL
      mutation($loginId: String!, $institution: String!, $requestId: String!) {
        createFlinksConnection(loginId: $loginId, institution: $institution, requestId: $requestId) {
          flinksConnection {
            id
            institution
            lastSyncedAt
          }
          errors
        }
      }
    GQL
  end

  it "creates a connection for the current user" do
    result = execute_graphql(mutation, variables: {
      "loginId" => "test-login-id",
      "institution" => "CIBC",
      "requestId" => "test-request-id"
    })

    data = result.dig("data", "createFlinksConnection")
    expect(data["errors"]).to be_empty
    expect(data["flinksConnection"]["institution"]).to eq("CIBC")

    conn = FlinksConnection.last
    expect(conn.user).to eq(current_user)
    expect(conn.institution).to eq("CIBC")
  end

  it "rejects duplicate institution for the same user" do
    FlinksConnection.create!(
      user: current_user,
      login_id: "existing",
      request_id: "existing",
      institution: "CIBC"
    )

    result = execute_graphql(mutation, variables: {
      "loginId" => "new-login",
      "institution" => "CIBC",
      "requestId" => "new-request"
    })

    data = result.dig("data", "createFlinksConnection")
    expect(data["errors"]).not_to be_empty
  end
end

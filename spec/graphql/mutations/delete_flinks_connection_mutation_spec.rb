# frozen_string_literal: true

require "rails_helper"

RSpec.describe "deleteFlinksConnection mutation" do
  fixtures :users

  let(:mutation) do
    <<~GQL
      mutation($id: ID!) {
        deleteFlinksConnection(id: $id) {
          success
          errors
        }
      }
    GQL
  end

  it "deletes the current user's connection" do
    alice = users(:alice)
    conn = FlinksConnection.create!(user: alice, login_id: "x", request_id: "y", institution: "CIBC")

    result = execute_graphql(mutation,
      variables: { "id" => conn.id.to_s },
      context: { current_user: alice })

    expect(result.dig("data", "deleteFlinksConnection", "success")).to be true
    expect(FlinksConnection.find_by(id: conn.id)).to be_nil
  end

  it "cannot delete another user's connection" do
    alice = users(:alice)
    bob = users(:bob)
    conn = FlinksConnection.create!(user: alice, login_id: "x", request_id: "y", institution: "CIBC")

    expect {
      execute_graphql(mutation,
        variables: { "id" => conn.id.to_s },
        context: { current_user: bob })
    }.to raise_error(ActiveRecord::RecordNotFound)
  end
end

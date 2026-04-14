module Mutations
  class CreateFlinksConnection < BaseMutation
    argument :login_id, String, required: true
    argument :institution, String, required: true
    argument :request_id, String, required: true

    field :flinks_connection, Types::FlinksConnectionType, null: true, connection: false
    field :errors, [String], null: false

    def resolve(login_id:, institution:, request_id:)
      conn = context[:current_user].flinks_connections.build(
        login_id: login_id,
        institution: institution,
        request_id: request_id
      )

      if conn.save
        { flinks_connection: conn, errors: [] }
      else
        { flinks_connection: nil, errors: conn.errors.full_messages }
      end
    end
  end
end

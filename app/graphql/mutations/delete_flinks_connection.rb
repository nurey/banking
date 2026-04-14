module Mutations
  class DeleteFlinksConnection < BaseMutation
    argument :id, ID, required: true

    field :success, Boolean, null: false
    field :errors, [String], null: false

    def resolve(id:)
      conn = context[:current_user].flinks_connections.find_by!(id: id)
      conn.destroy!
      { success: true, errors: [] }
    end
  end
end

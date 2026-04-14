module Mutations
  class TriggerFlinksImport < BaseMutation
    argument :days_back, Integer, required: false, default_value: 7

    field :success, Boolean, null: false
    field :errors, [String], null: false

    def resolve(days_back:)
      connections = context[:current_user].flinks_connections.where(status: "active")
      if connections.empty?
        return { success: false, errors: ["No active Flinks connections"] }
      end

      connections.each do |conn|
        Flinks::TransactionImporter.new(conn).import(days_back: days_back)
      end

      { success: true, errors: [] }
    rescue Flinks::ApiError => e
      { success: false, errors: [e.message] }
    end
  end
end

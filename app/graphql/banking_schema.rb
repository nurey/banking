class BankingSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  use GraphQL::Batch

  max_depth 10
  max_complexity 200

  disable_introspection_entry_points if Rails.env.production?
end

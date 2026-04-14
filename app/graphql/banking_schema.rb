class BankingSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  use GraphQL::Batch

  disable_introspection_entry_points if Rails.env.production?
end

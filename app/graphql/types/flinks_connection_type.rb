module Types
  class FlinksConnectionType < Types::BaseObject
    field :id, ID, null: false
    field :institution, String, null: false
    field :status, String, null: false
    field :last_synced_at, GraphQL::Types::ISO8601DateTime, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end

# frozen_string_literal: true

module GraphqlHelpers
  def execute_graphql(query, variables: {}, context: {})
    result = BankingSchema.execute(
      query,
      variables: variables,
      context: context
    )
    result.to_h
  end
end

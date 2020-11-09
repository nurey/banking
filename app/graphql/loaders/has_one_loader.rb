module Loaders
  class HasOneLoader < GraphQL::Batch::Loader
    def initialize(model, column)
      @model = model
      @column = column
    end

    def perform(relation_ids)
      @model.where({ @column => relation_ids.uniq }).each do |record|
        fulfill(record.public_send(@column), record)
      end
      relation_ids.each { |key| fulfill(key, nil) unless fulfilled?(key) }
    end
  end
end

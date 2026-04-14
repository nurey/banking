class FlinksImportJob < ApplicationJob
  queue_as :default
  retry_on Flinks::ApiError, wait: :polynomially_longer, attempts: 5
  discard_on Flinks::AuthenticationError

  def perform(days_back: 7)
    FlinksConnection.where(status: "active").find_each do |conn|
      result = Flinks::TransactionImporter.new(conn).import(days_back: days_back)
      Rails.logger.info("Flinks import for #{conn.institution} (user #{conn.user_id}): #{result}")
    rescue => e
      Rails.logger.error("Flinks import failed for connection #{conn.id}: #{e.message}")
      raise unless e.is_a?(Flinks::ApiError)
    end
  end
end

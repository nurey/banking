module Flinks
  class TransactionImporter
    def initialize(connection, client: Flinks::Client.new)
      @connection = connection
      @client = client
    end

    def import(days_back: 7)
      request_id = obtain_request_id
      transactions = @client.fetch_transactions(request_id: request_id)
      records = transactions.filter_map { |tx| transform(tx) }

      before_count = @connection.user.credit_card_transactions.count
      CreditCardTransaction.insert_all(records, unique_by: nil) if records.any?
      after_count = @connection.user.credit_card_transactions.count

      imported = after_count - before_count
      @connection.update!(last_synced_at: Time.current)

      { imported: imported, skipped: records.size - imported }
    end

    private

    def obtain_request_id
      auth = @client.authorize_with_login_id(login_id: @connection.login_id)
      @connection.update!(request_id: auth[:request_id])
      auth[:request_id]
    rescue Flinks::ApiError
      # Fall back to stored request_id if re-auth fails
      raise unless @connection.request_id.present?
      @connection.request_id
    end

    def transform(tx)
      debit = tx[:debit] ? (tx[:debit] * 100).round : nil
      credit = tx[:credit] ? (tx[:credit] * 100).round : nil

      return nil if debit.nil? && credit.nil?

      {
        user_id: @connection.user_id,
        tx_date: tx[:date],
        details: tx[:description],
        debit: debit,
        credit: credit,
        card_number: tx[:last_four_digits],
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end
end

class CreditCardTransactionSerializer
  include FastJsonapi::ObjectSerializer

  set_type :credit_card_transaction
  set_key_transform :dash

  attributes :tx_date, :details, :debit, :credit

  has_one :credit_transaction, serializer: CreditCardTransactionSerializer, if: Proc.new { |record|
    record.credit_transaction.present?
  }
end

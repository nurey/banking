# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # A row and what ClassifyRows took it for. `rate` is a tax row's printed
  # percentage; `quantity` is a quantity printed on the row (see Quantity).
  ClassifiedRow = Data.define(:row, :kind, :rate, :quantity) do
    %i[item quantity subtotal tax total payment other].each do |kind|
      define_method(:"#{kind}?") { self.kind == kind }
    end

    # @rbs return: String
    def text = row.text

    # @rbs return: Integer?
    def amount = row.amount
  end
end

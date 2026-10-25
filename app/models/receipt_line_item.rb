# rbs_inline: enabled
# frozen_string_literal: true

class ReceiptLineItem < ApplicationRecord
  belongs_to :receipt

  validates :line_total, presence: true
  validates :line_total, :unit_price, numericality: { only_integer: true, in: ReceiptParser::Money::RANGE }, allow_nil: true
  validates :qty, numericality: { greater_than: -10**7, less_than: 10**7 }, allow_nil: true # decimal(10, 3)
  validates :description, exclusion: { in: [ nil ], message: "can't be missing" }

  # @rbs return: Hash[Symbol, untyped]
  def as_api_json
    { position:, description:, qty: qty&.to_f, unit_price:, line_total: }
  end
end

# == Schema Information
#
# Table name: receipt_line_items
#
#  id          :bigint           not null, primary key
#  description :text             not null
#  line_total  :integer          not null
#  position    :integer          not null
#  qty         :decimal(10, 3)
#  sku         :text
#  unit_price  :integer
#  receipt_id  :bigint           not null
#
# Indexes
#
#  index_receipt_line_items_on_receipt_id               (receipt_id)
#  index_receipt_line_items_on_receipt_id_and_position  (receipt_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (receipt_id => receipts.id) ON DELETE => cascade
#

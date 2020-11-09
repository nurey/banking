# frozen_string_literal: true

class Note < ApplicationRecord
  belongs_to :credit_card_transaction
end


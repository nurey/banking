# frozen_string_literal: true

class Note < ApplicationRecord
  belongs_to :credit_card_transaction
end

# == Schema Information
#
# Table name: notes
#
#  id                         :bigint           not null, primary key
#  detail                     :text
#  credit_card_transaction_id :bigint
#
# Indexes
#
#  index_notes_on_credit_card_transaction_id  (credit_card_transaction_id)
#

# == Schema Information
#
# Table name: sessions
#
#  id         :bigint           not null, primary key
#  ip_address :string
#  token      :string           not null
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_sessions_on_token    (token) UNIQUE
#  index_sessions_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Session < ApplicationRecord
  belongs_to :user

  before_create { self.token = SecureRandom.urlsafe_base64(32) }
end

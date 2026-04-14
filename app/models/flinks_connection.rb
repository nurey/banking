# == Schema Information
#
# Table name: flinks_connections
#
#  id             :bigint           not null, primary key
#  institution    :string           not null
#  last_synced_at :datetime
#  status         :string           default("active"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  login_id       :string           not null
#  request_id     :string
#  user_id        :bigint           not null
#
# Indexes
#
#  index_flinks_connections_on_user_id                  (user_id)
#  index_flinks_connections_on_user_id_and_institution  (user_id,institution) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class FlinksConnection < ApplicationRecord
  belongs_to :user

  encrypts :login_id
  encrypts :request_id

  validates :institution, presence: true, uniqueness: { scope: :user_id }
end

class FlinksConnection < ApplicationRecord
  belongs_to :user

  encrypts :login_id
  encrypts :request_id

  validates :institution, presence: true, uniqueness: { scope: :user_id }
end

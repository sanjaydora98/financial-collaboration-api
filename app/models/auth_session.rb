class AuthSession < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, length: { is: 64 }, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
end
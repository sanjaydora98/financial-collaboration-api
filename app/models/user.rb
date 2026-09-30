class User < ApplicationRecord
  has_secure_password

  has_many :auth_sessions, dependent: :restrict_with_exception
  has_many :team_memberships, dependent: :restrict_with_exception
  has_many :teams, through: :team_memberships

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
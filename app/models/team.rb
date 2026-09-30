class Team < ApplicationRecord
  belongs_to :creator, class_name: "User", foreign_key: :created_by_id, inverse_of: :teams

  has_many :team_memberships, dependent: :restrict_with_exception
  has_many :users, through: :team_memberships
  has_many :expenses, dependent: :restrict_with_exception
  has_many :imports, dependent: :restrict_with_exception
  has_many :imported_transactions, dependent: :restrict_with_exception

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
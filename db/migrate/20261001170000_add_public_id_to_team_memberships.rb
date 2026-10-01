class AddPublicIdToTeamMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :team_memberships, :public_id, :uuid, default: -> { "gen_random_uuid()" }, null: false
    add_index :team_memberships, :public_id, unique: true
  end
end
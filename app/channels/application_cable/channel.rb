module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    def active_membership(team_id)
      current_user.team_memberships.find_by(team_id: team_id, active: true)
    end
  end
end

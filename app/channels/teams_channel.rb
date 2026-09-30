class TeamsChannel < ApplicationCable::Channel
  def subscribed
    membership = active_membership(params[:team_id])
    reject unless membership

    stream_from Realtime::Publisher.stream_name(membership.team_id)
  end
end
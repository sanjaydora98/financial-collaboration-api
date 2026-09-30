module Realtime
  class Publisher
    def self.stream_name(team_id)
      "team:#{team_id}"
    end

    def self.publish(team_id:, event:, resource:)
      ActionCable.server.broadcast(
        stream_name(team_id),
        { event: event, team_id: team_id, resource: resource }
      )
      true
    rescue StandardError => error
      Rails.logger.error("ActionCable broadcast failed event=#{event} team_id=#{team_id} error=#{error.class}: #{error.message}")
      false
    end
  end
end
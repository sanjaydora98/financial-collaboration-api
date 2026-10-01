class AuditLogSerializer
  def self.call(audit_log)
    actor = audit_log.actor_membership&.user

    {
      category: audit_log.category,
      event_type: audit_log.event_type,
      actor_type: audit_log.actor_type,
      actor: actor ? { name: actor.name, email: actor.email } : { name: "System", email: nil },
      created_at: audit_log.created_at,
      change_data: audit_log.change_data
    }
  end
end
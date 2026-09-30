class RenameAuditLogChangesToChangeData < ActiveRecord::Migration[7.1]
  def up
    if column_exists?(:audit_logs, :changes) && !column_exists?(:audit_logs, :change_data)
      rename_column :audit_logs, :changes, :change_data
    end
  end

  def down
    if column_exists?(:audit_logs, :change_data) && !column_exists?(:audit_logs, :changes)
      rename_column :audit_logs, :change_data, :changes
    end
  end
end

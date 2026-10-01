demo_password = "DemoPass123!"

user_details = {
	admin: ["demo.admin@example.com", "Avery Admin"],
	manager: ["demo.manager@example.com", "Morgan Manager"],
	finance: ["demo.finance@example.com", "Finley Finance"],
	viewer: ["demo.viewer@example.com", "Vera Viewer"]
}

users = user_details.to_h do |key, (email, name)|
	user = User.find_or_initialize_by(email: email)
	if user.new_record?
		user.name = name
		user.password = demo_password
		user.password_confirmation = demo_password
		user.save!
	end
	[key, user]
end

team = Team.find_or_initialize_by(slug: "northstar-studio")
if team.new_record?
	team.name = "Northstar Studio"
	team.creator = users.fetch(:admin)
	team.save!
end

membership_details = {
	admin: ["admin", nil],
	manager: ["approver", "manager"],
	finance: ["approver", "finance"],
	viewer: ["viewer", nil]
}

memberships = membership_details.to_h do |key, (role, stage)|
	membership = TeamMembership.find_or_initialize_by(team: team, user: users.fetch(key))
	if membership.new_record?
		membership.role = role
		membership.approval_stage = stage
		membership.active = true
		membership.save!
	end
	[key, membership]
end

expense_examples = [
	{ key: :draft, amount: "284.50", merchant: "Harbor Rail", description: "Client site visit", category: "Travel", day: 27 },
	{ key: :submitted, amount: "860.00", merchant: "Fieldnotes Hotel", description: "Product summit lodging", category: "Travel", day: 24 },
	{ key: :approved, amount: "412.30", merchant: "Juniper Kitchen", description: "Quarterly planning dinner", category: "Meals", day: 20 },
	{ key: :rejected, amount: "176.00", merchant: "The Copper Room", description: "Partner dinner outside policy", category: "Meals", day: 18 },
	{ key: :reimbursed, amount: "68.75", merchant: "MetroCab", description: "Airport transfer", category: "Travel", day: 15 }
]

expenses = expense_examples.to_h do |attributes|
	expense = Expense.find_or_initialize_by(team: team, description: attributes.fetch(:description))
	if expense.new_record?
		expense.assign_attributes(
			creator_membership: memberships.fetch(:viewer),
			member_membership: memberships.fetch(:viewer),
			amount: attributes.fetch(:amount),
			currency: "USD",
			merchant: attributes.fetch(:merchant),
			description: attributes.fetch(:description),
			category: attributes.fetch(:category),
			incurred_on: Date.new(2026, 9, attributes.fetch(:day)),
			status: ExpenseConstants::STATUSES.fetch(attributes.fetch(:key)),
			submitted_at: attributes.fetch(:key) == :draft ? nil : Time.current
		)
		expense.save!
	end
	[attributes.fetch(:key), expense]
end

approval_examples = {
	submitted: [
		[1, "manager", memberships.fetch(:manager), "pending", nil, nil],
		[2, "finance", memberships.fetch(:finance), "queued", nil, nil]
	],
	approved: [
		[1, "manager", memberships.fetch(:manager), "approved", "Manager approval", nil],
		[2, "finance", memberships.fetch(:finance), "approved", "Finance approval", nil]
	],
	rejected: [
		[1, "manager", memberships.fetch(:manager), "rejected", "Rejected as outside the travel policy.", "Outside policy"],
		[2, "finance", memberships.fetch(:finance), "skipped", "Finance review skipped", nil]
	],
	reimbursed: [
		[1, "manager", memberships.fetch(:manager), "approved", "Manager approval", nil],
		[2, "finance", memberships.fetch(:finance), "approved", "Finance approval", nil]
	]
}

approval_examples.each do |expense_key, records|
	records.each do |step, stage, approver, status, _label, rejection_reason|
		ExpenseApproval.find_or_create_by!(expense: expenses.fetch(expense_key), step: step) do |approval|
			approval.team = team
			approval.stage = stage
			approval.approver_membership = approver
			approval.status = status
			approval.acted_at = status.in?(%w[approved rejected skipped]) ? expenses.fetch(expense_key).created_at : nil
			approval.rejection_reason = rejection_reason
		end
	end
end

reimbursement_examples = [
	[expenses.fetch(:approved), "pending", nil],
	[expenses.fetch(:reimbursed), "paid", expenses.fetch(:reimbursed).created_at]
]

reimbursement_examples.each do |expense, status, paid_at|
	Reimbursement.find_or_create_by!(expense: expense) do |reimbursement|
		reimbursement.team = team
		reimbursement.initiated_by_membership = memberships.fetch(:admin)
		reimbursement.amount = expense.amount
		reimbursement.currency = expense.currency
		reimbursement.status = status
		reimbursement.paid_at = paid_at
	end
end

import = Import.find_or_initialize_by(team: team, idempotency_key: "northstar-demo-import-v1")
if import.new_record?
	import.requested_by_membership = memberships.fetch(:admin)
	import.provider = "demo-bank"
	import.status = "completed"
	import.started_at = Time.current
	import.finished_at = Time.current
	import.save!
end

transaction_examples = [
	["txn-pending-001", "pending", nil, nil],
	["txn-rejected-002", "rejected", memberships.fetch(:finance), "Duplicate personal purchase"]
]

transaction_examples.each_with_index do |(external_id, status, reviewer, reason), index|
	ImportedTransaction.find_or_create_by!(import: import, external_transaction_id: external_id) do |transaction|
		transaction.team = team
		transaction.provider = import.provider
		transaction.external_account_ref = "northstar-operating"
		transaction.amount = index.zero? ? "93.20" : "32.00"
		transaction.currency = "USD"
		transaction.merchant = index.zero? ? "City Bike Share" : "Personal Market"
		transaction.description = index.zero? ? "Client meeting transport" : "Non-business purchase"
		transaction.category = "Travel"
		transaction.transaction_date = Date.current - (index + 1).days
		transaction.status = status
		transaction.reviewed_by_membership = reviewer
		transaction.reviewed_at = reviewer ? import.created_at : nil
		transaction.rejection_reason = reason
	end
end

workflow_events = {
	submitted: [:submitted, memberships.fetch(:viewer)],
	approved: [:approved, memberships.fetch(:finance)],
	rejected: [:rejected, memberships.fetch(:manager)],
	reimbursed: [:reimbursement_paid, memberships.fetch(:admin)]
}

workflow_events.each do |expense_key, (event_type, actor)|
	AuditLog.find_or_create_by!(expense: expenses.fetch(expense_key), category: "workflow", event_type: event_type) do |audit|
		audit.team = team
		audit.actor_membership = actor
		audit.actor_type = "user"
		audit.change_data = { before: {}, after: { expense_status: expenses.fetch(expense_key).status } }
	end
end

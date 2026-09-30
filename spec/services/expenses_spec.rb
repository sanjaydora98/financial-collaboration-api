require "rails_helper"

RSpec.describe "Expense services" do
  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  it "rolls back expense and audit writes together when audit creation fails" do
    user = create_user("expense-service-rollback@example.com")
    team, membership = Teams::Create.call(user: user, attributes: { name: "Audit rollback", slug: "audit-rollback-service" })
    allow_any_instance_of(Expense).to receive(:record_crud_audit).and_raise(ActiveRecord::RecordNotSaved)

    expect {
      Expenses::Create.call(user: user, team: team, attributes: {
        amount: 15,
        currency: "USD",
        merchant: "Rollback",
        incurred_on: Date.current
      })
    }.to raise_error(ActiveRecord::RecordNotSaved)

    expect(Expense.where(team: team).count).to eq(0)
    expect(AuditLog.where(team: team).count).to eq(0)
    expect(membership).to be_active
  end
end
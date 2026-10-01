require "rails_helper"

RSpec.describe "Reimbursement services" do
  def create_context
    creator = User.create!(email: "reimbursement-service-#{SecureRandom.hex(4)}@example.com", name: "Creator", password: "password123")
    team, membership = Teams::Create.call(user: creator, attributes: { name: "Service reimbursement", slug: "service-reimbursement-#{SecureRandom.hex(4)}" })
    expense = Expense.create!(team: team, creator_membership: membership, member_membership: membership,
      amount: 45.25, currency: "CAD", merchant: "Hotel", incurred_on: Date.current, status: "approved")
    [creator, team, membership, expense]
  end

  it "rolls back reimbursement, expense status, and audits if the paid audit fails" do
    creator, team, _membership, expense = create_context
    allow(AuditLog).to receive(:create!).and_wrap_original do |original, attributes|
      raise ActiveRecord::RecordNotSaved if attributes[:event_type] == "reimbursement_paid"

      original.call(attributes)
    end

    expect {
      Reimbursements::Create.call(expense: expense, user: creator)
    }.to raise_error(ActiveRecord::RecordNotSaved)

    expect(expense.reload.status).to eq("approved")
    expect(expense.reimbursement).to be_nil
    expect(expense.audit_logs.where(category: "workflow").count).to eq(0)
    expect(Reimbursement.where(team: team).count).to eq(0)
  end

  it "rolls back failed settlement state and audit when the failure audit cannot be written" do
    creator, team, _membership, expense = create_context
    allow(Reimbursements::PaymentSimulator).to receive(:call).and_return(
      Reimbursements::PaymentSimulator::Result.new(status: "failed", failure_reason: "Simulated failure")
    )
    allow(AuditLog).to receive(:create!).and_wrap_original do |original, attributes|
      raise ActiveRecord::RecordNotSaved if attributes[:event_type] == "reimbursement_failed"

      original.call(attributes)
    end

    expect {
      Reimbursements::Create.call(expense: expense, user: creator)
    }.to raise_error(ActiveRecord::RecordNotSaved)

    expect(expense.reload.status).to eq("approved")
    expect(expense.reimbursement).to be_nil
    expect(expense.audit_logs.where(category: "workflow").count).to eq(0)
    expect(Reimbursement.where(team: team).count).to eq(0)
  end

  it "rejects partial amount or mismatched currency at model validation" do
    creator, team, membership, expense = create_context

    partial = Reimbursement.new(team: team, expense: expense, initiated_by_membership: membership,
      amount: 20, currency: "CAD", status: "pending")
    expect(partial).not_to be_valid
    expect(partial.errors[:amount]).to be_present

    wrong_currency = Reimbursement.new(team: team, expense: expense, initiated_by_membership: membership,
      amount: expense.amount, currency: "USD", status: "pending")
    expect(wrong_currency).not_to be_valid
    expect(wrong_currency.errors[:currency]).to be_present
    expect(creator).to be_persisted
  end

  it "retries a failed reimbursement through the explicit service using the same row" do
    creator, _team, _membership, expense = create_context
    allow(Reimbursements::PaymentSimulator).to receive(:call).and_return(
      Reimbursements::PaymentSimulator::Result.new(status: "failed", failure_reason: "Temporary settlement failure")
    )
    reimbursement = Reimbursements::Create.call(expense: expense, user: creator)
    reimbursement_id = reimbursement.id
    expect(expense.reload.status).to eq("approved")

    allow(Reimbursements::PaymentSimulator).to receive(:call).and_return(
      Reimbursements::PaymentSimulator::Result.new(status: "paid")
    )
    retried = Reimbursements::Retry.call(reimbursement: reimbursement, user: creator)

    expect(retried.id).to eq(reimbursement_id)
    expect(retried.status).to eq("paid")
    expect(retried.failure_reason).to be_nil
    expect(expense.reload.status).to eq("reimbursed")
    expect(expense.audit_logs.where(category: "workflow").order(:id).pluck(:event_type)).to eq(
      %w[reimbursement_initiated reimbursement_failed reimbursement_initiated reimbursement_paid]
    )
  end
end
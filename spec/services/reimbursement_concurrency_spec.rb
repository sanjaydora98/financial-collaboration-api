require "rails_helper"

RSpec.describe "Reimbursement concurrency" do
  self.use_transactional_tests = false

  before do
    @creator = User.create!(email: "reimbursement-race-#{SecureRandom.hex(4)}@example.com", name: "Race creator", password: "password123")
    @team, @membership = Teams::Create.call(
      user: @creator,
      attributes: { name: "Reimbursement race", slug: "reimbursement-race-#{SecureRandom.hex(4)}" }
    )
    @expense = Expense.create!(
      team: @team,
      creator_membership: @membership,
      member_membership: @membership,
      amount: 65,
      currency: "USD",
      merchant: "Race expense",
      incurred_on: Date.current,
      status: "approved"
    )
  end

  after do
    AuditLog.where(team_id: @team.id).delete_all
    Reimbursement.where(team_id: @team.id).delete_all
    Expense.where(team_id: @team.id).delete_all
    TeamMembership.where(team_id: @team.id).delete_all
    Team.where(id: @team.id).delete_all
    User.where(id: @creator.id).delete_all
  end

  it "allows only one of two simultaneous requests to create and settle reimbursement" do
    ready = Queue.new
    start = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            Reimbursements::Create.call(
              expense: Expense.find(@expense.id),
              user: User.find(@creator.id)
            )
            results << :success
          rescue Reimbursements::Conflict
            results << :conflict
          rescue StandardError => error
            results << error
          end
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    expect(outcomes.count(:success)).to eq(1)
    expect(outcomes.count(:conflict)).to eq(1)
    expect(Reimbursement.where(expense_id: @expense.id).count).to eq(1)
    expect(@expense.reload.status).to eq("reimbursed")
  end
end
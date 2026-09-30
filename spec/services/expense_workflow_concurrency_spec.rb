require "rails_helper"

RSpec.describe "Expense workflow concurrency" do
  self.use_transactional_tests = false

  before do
    @creator = create_user("workflow-race-creator-#{SecureRandom.hex(4)}@example.com")
    @team, @creator_membership = Teams::Create.call(
      user: @creator,
      attributes: { name: "Race workflow", slug: "race-workflow-#{SecureRandom.hex(4)}" }
    )
    @manager = create_user("workflow-race-manager-#{SecureRandom.hex(4)}@example.com")
    @manager_membership = TeamMembership.create!(team: @team, user: @manager, role: "approver", approval_stage: "manager")
    @finance = create_user("workflow-race-finance-#{SecureRandom.hex(4)}@example.com")
    TeamMembership.create!(team: @team, user: @finance, role: "approver", approval_stage: "finance")
    @expense = Expense.create!(team: @team, creator_membership: @creator_membership, member_membership: @creator_membership,
      amount: 30, currency: "USD", merchant: "Concurrency", incurred_on: Date.current)
  end

  after do
    AuditLog.where(team_id: @team.id).delete_all
    ExpenseApproval.where(team_id: @team.id).delete_all
    Expense.where(team_id: @team.id).delete_all
    TeamMembership.where(team_id: @team.id).delete_all
    Team.where(id: @team.id).delete_all
    User.where(id: [@creator.id, @manager.id, @finance.id]).delete_all
  end

  it "serializes concurrent submissions and creates only one pair of approvals" do
    results = race_two do
      Expenses::Submit.call(expense: Expense.find(@expense.id), user: User.find(@creator.id))
    end

    expect(results.count(:success)).to eq(1)
    expect(results.count(:conflict)).to eq(1)
    expect(@expense.expense_approvals.count).to eq(2)
    expect(@expense.reload.status).to eq("submitted")
  end

  it "allows only one of two concurrent Manager approvals" do
    submit_expense
    results = race_two do
      Expenses::Review.call(expense: Expense.find(@expense.id), user: User.find(@manager.id), decision: "approve")
    end

    expect(results.count(:success)).to eq(1)
    expect(results.count(:conflict)).to eq(1)
    expect(@expense.expense_approvals.find_by!(stage: "manager").status).to eq("approved")
    expect(@expense.expense_approvals.find_by!(stage: "finance").status).to eq("pending")
  end

  it "allows only one of two concurrent Manager rejections" do
    submit_expense
    results = race_two do
      Expenses::Review.call(
        expense: Expense.find(@expense.id),
        user: User.find(@manager.id),
        decision: "reject",
        rejection_reason: "Duplicate decision"
      )
    end

    expect(results.count(:success)).to eq(1)
    expect(results.count(:conflict)).to eq(1)
    expect(@expense.reload.status).to eq("rejected")
    expect(@expense.expense_approvals.find_by!(stage: "manager").status).to eq("rejected")
  end

  it "allows only one winner when Manager approval races with rejection" do
    submit_expense
    results = race_two(%w[approve reject]) do |decision|
      options = decision == "reject" ? { rejection_reason: "Racing rejection" } : {}
      Expenses::Review.call(
        expense: Expense.find(@expense.id),
        user: User.find(@manager.id),
        decision: decision,
        **options
      )
    end

    expect(results.count(:success)).to eq(1)
    expect(results.count(:conflict)).to eq(1)
    expect(%w[approved rejected]).to include(@expense.expense_approvals.find_by!(stage: "manager").status)
  end

  private

  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def submit_expense
    Expenses::Submit.call(expense: @expense, user: @creator)
  end

  def race_two(arguments = [nil, nil], &operation)
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = arguments.map do |argument|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            operation.call(argument)
            results << :success
          rescue Expenses::WorkflowConflict
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
    2.times.map { results.pop }
  end
end
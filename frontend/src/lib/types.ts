export type User = {
  id: number;
  email: string;
  name: string;
};

export type TeamMembership = {
  id: number;
  user_id: number;
  role: "creator" | "approver" | "viewer" | "admin";
  approval_stage?: string | null;
  active: boolean;
};

export type Team = {
  id: number;
  name: string;
  slug: string;
  created_by_id: number;
  membership?: TeamMembership;
};

export type Expense = {
  id: number;
  team_id: number;
  creator_membership_id: number;
  member_membership_id: number;
  amount: number;
  currency: string;
  merchant: string;
  description?: string | null;
  category?: string | null;
  incurred_on: string;
  status: string;
  lock_version: number;
  created_at: string;
  updated_at: string;
};

export type ImportRecord = {
  id: number;
  team_id: number;
  requested_by_membership_id: number;
  provider: string;
  idempotency_key?: string | null;
  status: string;
  started_at?: string | null;
  finished_at?: string | null;
  error_summary?: string | null;
  imported_transaction_count: number;
};

export type ImportedTransaction = {
  id: number;
  team_id: number;
  import_id: number;
  provider: string;
  external_account_ref?: string | null;
  external_transaction_id?: string | null;
  amount: number;
  currency: string;
  merchant?: string | null;
  description?: string | null;
  category?: string | null;
  transaction_date: string;
  status: string;
  reviewed_by_membership_id?: number | null;
  reviewed_at?: string | null;
  rejection_reason?: string | null;
};

export type ApprovalRecord = {
  id: number;
  step: number;
  stage: string;
  approver_membership_id: number;
  status: string;
  acted_at?: string | null;
  rejection_reason?: string | null;
};

export type Reimbursement = {
  id: number;
  expense_id: number;
  initiated_by_membership_id: number;
  amount: number;
  currency: string;
  status: string;
  paid_at?: string | null;
  failure_reason?: string | null;
};

export type AuthPayload = {
  user: User;
  token: string;
  expires_at: string;
};

export type ApiErrorPayload = {
  error?: {
    code?: string;
    message?: string;
    details?: Record<string, string[] | string>;
    current_lock_version?: number;
  };
};

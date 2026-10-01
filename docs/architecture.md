# Architecture

## Overview

The application is a single Rails 7.1 API monolith. PostgreSQL is the source of truth for teams, expenses, approvals, reimbursements, imports, and audit history. Redis backs Sidekiq and ActionCable. Controllers handle HTTP concerns, Pundit policies authorize actions, and focused service objects own business transactions. No microservices, event-sourcing platform, or generic workflow engine is needed.

The application is configured API-only. This document describes the implemented design and its explicit take-home assumptions.

## Domains and components

- **Identity:** `User` and `AuthSession` authenticate API requests and maintain revocable sessions.
- **Teams:** `Team` and `TeamMembership` represent multi-team membership and per-team roles.
- **Expenses:** `Expense` stores the person to whom an expense is attributed separately from the membership that created it. `ExpenseApproval` stores ordered approval assignments.
- **Reimbursements:** `Reimbursement` tracks payout independently from expense approval.
- **Imports:** `Import` records a provider import request; `ImportedTransaction` stores normalized provider rows for review and possible expense creation.
- **Audit:** `AuditLog` records mandatory expense CRUD events and optional workflow events.
- **Asynchronous and live updates:** Sidekiq runs import jobs; ActionCable broadcasts committed changes to authorized team members.

Keep services small and explicit: `Expenses::Create`, `Expenses::Update`, `Expenses::Delete`, `Expenses::Submit`, `Expenses::Review`, `ImportedTransactions::BulkReview`, `Reimbursements::Create`, `Imports::Request`, and `Imports::Process`. Services validate transitions, establish actor context, and coordinate writes. Jobs call the same services rather than duplicating business rules.

Controllers authenticate first, scope record lookup to the user's active team membership, authorize with Pundit, invoke a service, and render JSON. Never load a tenant-owned row globally and then rely on a policy check to prevent cross-team access.

## Expense creator, member, and permissions

`Expense.creator_membership_id` identifies who entered the expense. `Expense.member_membership_id` identifies the team member to whom it is attributed. They are distinct even when they usually refer to the same membership. The expense's member is the subject of the expense; the creator is its author.

| Team role | Permissions |
| --- | --- |
| `creator` | Create expenses attributed to their own membership; read expenses they created or to which they are attributed; edit or logically delete only their own expenses while they are drafts. Cannot create for another member or approve. |
| `approver` | Read team expenses; approve or reject only an assigned, currently pending approval step. Cannot edit expense fields or approve an unassigned step. |
| `viewer` | Read team expenses and relevant team activity. Strictly read-only. |
| `admin` | Manage team memberships and team expense records, including creating an expense attributed to another member and editing/deleting any unsubmitted expense. Admin actions do not bypass approval or reimbursement workflow. An admin may approve only when their admin membership has the matching `approval_stage` and is the assigned approver; a stage-null admin cannot approve. |

### Team membership bootstrap

Creating a team transactionally creates exactly one active `creator` membership for the authenticated user. Because membership administration is otherwise admin-only, the team creator may promote that same active membership from `creator` to `admin`. This is the only bootstrap path: it cannot target another user or create another membership. The promotion is transactional. Self-demotion and self-deactivation are not exposed; an administrator also cannot demote or deactivate the last active admin, so a team cannot be left unmanageable through membership operations. Membership changes are not written to `AuditLog`: the approved audit table is expense-scoped and the architecture only requires expense CRUD audit records.

Active team members may list team memberships. Only admins may add, update, or deactivate another member. Deactivation sets `active = false`; it does not delete the membership row, preserving the one-membership-per-user/team constraint. Creators who are not admins have only the explicit self-promotion bootstrap action for membership administration.

Pundit policies receive the authenticated user and target team, resolve an active membership for that exact team, then check role and (for approval authorization) stage and the assigned pending approval row. Team resource loading starts from active memberships and is team-scoped; cross-team IDs return not found. Team creation requires authentication but does not grant access to any other team.

Only an admin may create an expense for another member. The service checks both memberships are active in the same team, records the acting admin as creator and the chosen member as the expense member, and writes the normal create audit event. Pundit policies check the team role and record ownership/assignment; scoped lookup prevents cross-team identifiers from exposing data. Return `404` for records outside the caller's teams and `403` for a known in-team action the caller is not allowed to perform.

Rejected expenses are terminal in the stated assignment lifecycle; no resubmission transition is assumed. Logical deletion is available to the creator for their own draft and to an admin for an unsubmitted expense. Financial history is not physically deleted. Approved or reimbursed records cannot be altered or deleted to bypass the workflow.

## Authentication

Use `has_secure_password` with an explicitly declared `bcrypt` dependency. Generate a cryptographically random opaque bearer token with at least 256 bits of entropy. Return the raw token once; persist only its SHA-256 hex digest in `AuthSession.token_digest`. On each request, hash the presented token, find the matching session by its unique digest, and reject missing, expired, revoked, or disabled-user sessions. The authentication layer sets `current_user` and the active `current_membership` after the team is selected and verified.

Logout sets `revoked_at`; expiration is checked on every request. Do not log bearer tokens. ActionCable obtains a one-minute signed connection ticket from an authenticated API request. The ticket contains the session ID, not the bearer token; the connection rechecks that the session remains active and the user remains enabled, then the channel authorizes active team membership before subscribing.

## Expense and approval workflow

Expense states are `draft -> submitted -> approved -> reimbursed`, with `submitted -> rejected`. Services enforce this transition graph; controllers cannot assign status directly.

On submission, create Manager step 1 as `pending` and Finance step 2 as `queued`. Manager approval marks step 1 approved and activates step 2. Finance approval marks step 2 approved and moves the expense to `approved`. Rejection records its reason and decision time, moves the expense to `rejected`, and marks any later queued steps `skipped`. Only the assigned active approver can act.

The API keeps the expense state `submitted` while awaiting approvals; `pending` and `queued` are approval-row states, not additional expense states. Submission and review are transactional. A workflow audit event uses `change_data.before` and `change_data.after` for expense/approval statuses, stage, decision, and (on rejection) reason. Expense status changes also retain the required separate CRUD audit callback. If a team has no active Manager or Finance assignment, submission returns `422` and creates no partial workflow data. Repeated or out-of-order workflow actions return `409`.

**Approval assignment assumption:** for this take-home, each team has at most one active Manager approver and one active Finance approver. `TeamMembership.approval_stage` records the stage for an `approver`, or optionally for an `admin` who is also eligible to approve. Creator and viewer memberships must have no approval stage. A normal admin with a null stage cannot approve. `ExpenseApproval` is modeled as one assignment per approver per expense step, so a later version can allow multiple approvers at one stage by removing the one-active-membership-per-stage limit and defining the stage's group-decision rule. The ordered step data remains usable; no generic workflow engine is introduced.

## Reimbursement

An approved expense may have one reimbursement, with states `pending`, `processing`, `paid`, `failed`, or `cancelled`. A failed reimbursement can be retried through an explicit service transition; `paid` is terminal. A paid reimbursement and its expense's transition to `reimbursed` commit atomically. Reimbursement amount and currency are stored explicitly and must match the approved expense for a full reimbursement; partial reimbursements are out of scope for this take-home.

For this take-home, a `creator` may initiate reimbursement only for an approved expense they created. An `admin` may initiate reimbursement for any approved, non-deleted expense in their team. `approver` and `viewer` memberships cannot initiate reimbursement. The active authenticated membership is recorded as `initiated_by_membership_id`; cross-team lookup remains hidden. The endpoint uses an internal payment simulation rather than an external provider.

## Audit strategy

Every successful Expense create, update, and logical delete produces one `AuditLog` CRUD row. Centralize these writes in `Expense` create/update callbacks that run inside the Active Record save transaction. The request/job sets actor context (`current_membership` or system actor), and the delete service marks `deleted_at`, which the audit writer classifies as `delete`. A normal field change is `update`. Avoid `update_columns`, `delete_all`, direct SQL mutation of expenses, and physical deletes because they bypass callbacks and violate this invariant. Tests must verify CRUD paths and rollback behavior.

CRUD events are separate from workflow events. Submission, approval/rejection, reimbursement initiation/payment/failure, and imported-transaction acceptance may add `workflow` audit rows with named event types. An approval or reimbursement that updates the expense therefore has its required CRUD `update` row plus a distinct workflow event. The JSONB `audit_logs.change_data` column stores relevant before/after business fields as `{ "before": { ... }, "after": { ... } }`. Create events use an empty `before`; update and logical-delete events include only changed business attributes. Lock/timestamp bookkeeping is omitted. `AuditLog` rows are append-only and never contain secrets or raw provider credentials.

## Transaction boundaries

Every business mutation and the audit rows that describe it share one PostgreSQL transaction:

| Operation | Atomic writes |
| --- | --- |
| Expense create | Expense and its create audit row. |
| Expense update | Expense update and its update audit row. |
| Expense delete | Logical-delete update and its delete audit row. |
| Expense submission | Expense status/timestamp, both approval assignment rows, and submission workflow audit row. |
| Approval decision | Approval decision/reason/timestamp, any next-step activation or skip, expense status, and workflow audit row. Expense CRUD callback audit is in the same transaction. |
| Reimbursement payment | Reimbursement status/timestamp, expense status, and workflow audit row. Expense CRUD callback audit is in the same transaction. |
| Imported transaction acceptance | Lock/review the imported transaction, create the expense, mark the transaction accepted, and write workflow audit. Expense create audit is in the same transaction. |
| Bulk review | Preauthorize the full team-scoped ID set, then process each item in its own transaction and return one result per ID. Successful items remain committed when another item conflicts or fails validation. |

Team creation and its initial membership are also atomic. Import batch progress can be recorded in separate transactions; each provider row's idempotency claim and writes must be atomic. External network calls do not occur inside database transactions.

## Concurrency and error handling

`expenses.lock_version` enables Rails optimistic locking. Update requests include the version the client read. Active Record detects a stale version and raises `ActiveRecord::StaleObjectError`; map this to HTTP `409 Conflict` with a stable error code and the current version. Never silently retry a user's stale field update over another user's changes. The client must fetch current data and choose how to reconcile.

Expense list/show/update/delete routes are nested beneath a team and begin from the caller's active-team scope. Deleted expenses are excluded from normal reads. Expense writes accept only editable business fields; creation always sets `draft`, and the creator/member membership IDs are server-derived or validated against active memberships in that team. `lock_version` is required on update and logical delete.

For approval and import state transitions, lock the relevant row(s) with `SELECT ... FOR UPDATE`, recheck current status and authorization, then write. Database unique constraints remain the final defense against races. Map validation failures to `422`, unauthenticated requests to `401`, in-team forbidden actions to `403`, cross-team/missing records to `404`, and optimistic-lock or idempotency/state conflicts to `409`. Return a consistent JSON error shape without leaking another team's data.

## Imports and idempotency

`Import` uses `queued -> running -> completed/failed`; `ImportedTransaction.status = pending` is the pending-review state and transitions to `accepted` or `rejected`. The API persists the Import and enqueues `Imports::ProcessJob` with its stable ID and a whitelisted JSON payload. The job loads the Import and delegates to `Imports::Process`; it does not duplicate domain behavior. The import request key `(team_id, provider, idempotency_key)` deduplicates starting a batch. The external transaction key `(team_id, provider, external_account_ref, external_transaction_id)` deduplicates provider rows across batches and retries. PostgreSQL unique indexes enforce both; processing uses `INSERT ... ON CONFLICT DO NOTHING` against the external identity index. The unique `expenses.imported_transaction_id` remains the final guard against duplicate expenses.

Sidekiq is at-least-once: the Import row lock serializes duplicate jobs, completed Imports are no-ops, failed Imports may be retried, and external rows use the database unique index. Import status plus all rows for a processing attempt commit in one transaction. If a worker fails after inserts but before completion, PostgreSQL rolls the entire attempt back; the error is recorded as `failed` after rollback. A retry can safely replay the JSON job payload. The payload contains only whitelisted transaction data, not credentials or raw secrets; it is stored in Sidekiq's Redis job arguments because Stage 0-8 has no Import payload column.

Active team members may inspect imports and transactions. `creator`, `approver`, and `admin` memberships may start an import; viewers are read-only. Only active `admin` and `approver` memberships may accept or reject a pending transaction. All lookups are team-scoped.

Acceptance locks the transaction and atomically creates an Expense, marks the transaction accepted, records the reviewer, and writes the existing `import_accepted` expense audit. Expense creator and attributed member are both the active membership that requested the Import; the reviewer remains the review/audit actor. This is the deterministic mapping because the external payload does not identify a team membership. Do not infer one from account references or other transaction fields; explicit external-account mapping is outside this take-home.
The optional external transaction category is persisted and carried through to the resulting Expense; when the incoming payload omits category, the Expense category remains unset.

Rejection requires a reason and atomically records `rejected`, reviewer membership, timestamp, and reason. AuditLog remains intentionally expense-scoped. Imported transactions rejected before expense creation retain their review history directly on ImportedTransaction; no separate AuditLog record is created. Accepted transactions retain the existing `import_accepted` Expense audit. No external integration is used.

Bulk review is restricted to active `admin` and `approver` memberships. The controller verifies every requested ID belongs to the requested team and preauthorizes the whole set before mutating any item. It then invokes the existing single-item accept/reject service separately for each transaction, so each transaction/review/Expense/audit unit is atomic without holding one transaction across an arbitrarily large batch. Results are reported per ID (`accepted`, `rejected`, `conflict`, or `validation_error`); mixed state conflicts return HTTP `409` with the full result list. Concurrent single or bulk review is serialized by each ImportedTransaction row lock; unique external identity and one-expense-per-import constraints remain final guards.

## Real-time collaboration

ActionCable uses the configured Redis adapter. Authorize active membership before subscribing to a team stream. Broadcast small committed events (for example `expense.updated`, `approval.completed`, and `reimbursement.updated`) only after transaction commit. Clients retrieve full records through the normal team-scoped API. This avoids broadcasting rolled-back data or treating a channel as an authorization bypass.

## Testing strategy

- Request specs: bearer auth, session expiry/revocation, role permissions, team isolation, lifecycle endpoints, error mapping, and bulk requests.
- Service/model specs: state transitions, creator-versus-member behavior, audit creation and rollback, approval assignment rules, and reimbursement consistency.
- PostgreSQL constraint specs: checks, foreign keys, and all uniqueness guarantees, including tenant-matching composite foreign keys.
- Job specs: retries, duplicate batches, duplicate external transactions, and concurrent acceptance.
- Locking specs: stale `lock_version` returns `409` without overwriting the newer value.
- ActionCable specs: unauthorized subscriptions are rejected and authorized broadcasts occur only after commit.
- Use separate database connections for race/concurrency tests. Transactional fixtures alone cannot demonstrate competing commits.

## Trade-offs

- `bcrypt` is an explicit Gemfile dependency for `has_secure_password`.
- Team-matching composite foreign keys protect tenant references at the database boundary but are more involved than scalar Rails associations. Keep Rails associations on scalar IDs and add only the composite constraints documented in `database_design.md`.
- Rails 7.1/PostgreSQL migrations must be tested for schema dump/load round-tripping of composite constraints. Use the Rails migration DSL when it can represent the constraint; otherwise use named, reversible SQL. This app sets SQL schema format and tracks `db/structure.sql` as the authoritative schema so composite constraints are retained.
- The one-manager/one-finance assignment and full reimbursement are explicit take-home assumptions, not universal workflow rules.
# Expense Collaboration Platform

## Overview

A team-scoped expense collaboration application with a Rails JSON API and a separate Next.js frontend. It supports authenticated teams, expense approvals, reimbursement simulation, transaction import/review, audit history, and live team updates.

## Architecture

```text
Next.js / React frontend -> Rails API -> PostgreSQL
											 |          source of truth
											 +-> Redis -> Sidekiq import jobs
											 |       +--> ActionCable broadcasts
```

PostgreSQL is authoritative for financial and workflow state. Redis is used for job transport and ActionCable pub/sub, not as a replacement for persisted business data. Rails controllers handle HTTP, Pundit policies enforce authorization, and service objects own transactional domain changes.

See [docs/architecture.md](docs/architecture.md) and [docs/database_design.md](docs/database_design.md) for implementation details and constraints.

## Main Features

- Bearer authentication with expiring and revocable sessions
- Team membership and role-based authorization
- Expense creation, editing, logical deletion, and optimistic locking
- Ordered Manager and Finance approval workflow with rejection paths
- Reimbursement state tracking through an internal payment simulator
- Idempotent transaction imports processed by Sidekiq
- Individual and bulk imported-transaction review with per-item outcomes
- Expense-scoped audit trail
- ActionCable updates for authorized team members

## Tech Stack

Backend: Ruby 3.0.3, Rails 7.1, PostgreSQL, Sidekiq, Redis, Pundit, RSpec.

Frontend: Next.js 16, React 19, TypeScript, Vitest, Testing Library.

## Local Setup

Prerequisites: Ruby 3.0.3, PostgreSQL, Redis, and Node.js 20.9 or newer. Start PostgreSQL and Redis using your platform's service manager. The default local configuration expects PostgreSQL on its standard local socket and Redis at `localhost:6379`.

1. From the repository root, install Ruby dependencies and prepare the database:
	```bash
	bundle install
	bin/rails db:prepare
	bin/rails db:migrate
	bin/rails db:seed
	```
2. Optional backend environment overrides (the defaults below work locally):
	```bash
	export SIDEKIQ_REDIS_URL=redis://localhost:6379/0
	export ACTION_CABLE_REDIS_URL=redis://localhost:6379/1
	export FRONTEND_ORIGIN=http://localhost:3001
	```
	`.env.example` contains safe examples but Rails does not automatically load `.env`. `EXPENSE_COLLAB_DATABASE_PASSWORD` is used by the production database configuration.
3. Start the Rails API in one terminal:
	```bash
	bin/rails server
	```
4. Start the Sidekiq worker in another terminal:
	```bash
	bundle exec sidekiq
	```
5. Install and run the frontend in a third terminal:
	```bash
	cd frontend
	cp .env.example .env.local
	npm install
	npm run dev
	```

The API is available at `http://localhost:3000`; the frontend is at `http://localhost:3001`. The frontend uses `NEXT_PUBLIC_API_URL` from `frontend/.env.local`, defaulting to the local API. Rails uses `FRONTEND_ORIGIN` to restrict HTTP CORS and ActionCable origins to the frontend origin.

## Test Commands

Run from the repository root:

```bash
bundle check
bin/rails zeitwerk:check
bundle exec rspec
```

Run from `frontend/`:

```bash
npm install
npm run test
npm run lint
npm run build
```

## Demo Flow

Demo users are seeded with the same local-only password, `DemoPass123!`:

- `demo.admin@example.com` (team admin)
- `demo.manager@example.com` (Manager approver)
- `demo.finance@example.com` (Finance approver)
- `demo.viewer@example.com` (viewer)

These credentials are for local/demo environments only. `bin/rails db:seed` is safe to rerun.

1. Register or log in through the frontend.
2. Create a team through authenticated `POST /teams`; promote its initial creator membership with `POST /teams/:id/bootstrap_admin`.
3. Provision one Manager and one Finance approver using the protected team-membership API. Team creation and role provisioning are API workflows; the MVP frontend currently selects existing teams and displays memberships.
4. Create an expense in the frontend, edit it while it is a draft, then submit it.
5. Sign in as the assigned Manager and approve, then sign in as the assigned Finance approver and approve.
6. Create a reimbursement and confirm the simulated payout changes the expense to reimbursed.
7. Submit a JSON transaction batch from Imports while Sidekiq is running; review the queued/completed import.
8. Accept or reject imported transactions, then demonstrate bulk review with mixed item outcomes.
9. Open the approval queue in one browser session and submit an expense in another; the queue refreshes from the ActionCable event without a manual reload.

## Architecture Decisions / Tradeoffs

- PostgreSQL is the source of truth; database constraints backstop service validations and race-prone uniqueness rules.
- Service objects coordinate state transitions, actor context, audit writes, and transaction boundaries.
- Pundit policies and team-scoped lookups enforce tenant authorization on the backend; frontend restrictions are only UX.
- Expense updates require `lock_version`; stale updates return `409 Conflict` instead of overwriting newer data.
- Unique indexes protect team membership, approval assignments, import idempotency, external transaction identity, and one expense per imported transaction.
- Idempotency keys make import requests and provider transaction ingestion replay-safe.
- Sidekiq processing is at-least-once; workers lock imports and rely on PostgreSQL uniqueness to make retries safe.
- ActionCable broadcasts committed, small events to team streams; clients refetch full resources through authorized API endpoints. Browser sockets use short-lived signed tickets tied to active sessions, not bearer tokens in URLs.
- Bulk review uses separate per-item transactions so one conflict does not erase successful decisions; the response reports each outcome.
- Audit history is expense-scoped. Rejected imported rows retain their review data on the imported-transaction record rather than creating an unrelated audit row.

## Concurrency

Rails optimistic locking protects expense edits using `lock_version`. Workflow reviews and reimbursements lock their affected rows and recheck state. Database unique constraints are the final guard for duplicate submissions, imported transactions, and resulting expenses. Import workers may be retried; their database claims and writes are idempotent. A stale client must reload and reconcile rather than retrying its old values automatically.

## Known Limitations

- Reimbursements use an internal simulator; no payment provider is connected.
- Imports accept normalized JSON transaction batches; there is no external bank/provider integration.
- A team supports one active Manager and one active Finance assignment for this take-home workflow.
- Team creation and membership role provisioning are available through the API, not the current frontend screens.
- The approval queue lists submitted team expenses broadly instead of filtering to the current user's assigned step; the API still enforces assignment and returns conflicts for stale or out-of-order decisions.
- Import completion is fetched through the API but is not broadcast over ActionCable; refresh the import view to see background processing finish.
- The frontend is an evaluator-oriented MVP; it stores the bearer token in browser localStorage and is not a hardened enterprise identity client.
- Automated tests cover API, service, concurrency, and key frontend behavior; a live multi-browser Redis/ActionCable session still requires the local services described above.

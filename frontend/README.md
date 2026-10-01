# Expense Collab Frontend

This frontend is a lightweight Next.js app that speaks to the Rails API in this repository. See the [root README](../README.md) for full architecture, local service startup, and evaluator walkthrough.

## Setup

1. Start PostgreSQL and Redis, then start the Rails API and Sidekiq as described in the root README.
2. In this directory, copy the example environment file:
   ```bash
   cp .env.example .env.local
   ```
3. Start the frontend:
   ```bash
   npm install
   npm run dev
   ```

The frontend runs on port 3001 by default and talks to the Rails API using `NEXT_PUBLIC_API_URL` (default: `http://localhost:3000`). Set Rails `FRONTEND_ORIGIN` to this frontend origin so HTTP CORS and ActionCable accept it.

## Authentication

The app stores the bearer token in `localStorage` and sends it using the `Authorization: Bearer <token>` header for authenticated requests. The Rails API remains the source of truth for authentication, authorization, and domain validation; frontend checks provide immediate browser feedback only.

## Frontend validations

- Login and registration use native form validation: required fields and email format are checked by the browser.
- Expense forms require an amount, merchant, currency, and incurred date. Amounts must be at least `0.01` and use two-decimal input steps; currency is limited to three characters.
- Team creation and join forms require non-empty values. Team codes are trimmed and normalized to lowercase before submission.
- Import submission parses the transaction textarea as JSON before sending it to the API. Import idempotency keys and provider values are submitted for server-side validation and replay protection.
- Bulk transaction review disables actions when no transactions are selected and reports per-item conflicts or validation errors returned by the API.
- API errors are converted into user-facing messages, including field-level validation details when the Rails response provides them.

The frontend does not duplicate the backend's full business rules. The API validates permissions, tenant membership, monetary formats, workflow transitions, optimistic-lock versions, and import/review constraints.

## Useful scripts

```bash
npm run dev
npm run build
npm run test
npm run lint
```

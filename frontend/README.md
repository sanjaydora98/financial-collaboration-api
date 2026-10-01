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

The app stores the bearer token in localStorage and sends it using the `Authorization: Bearer <token>` header for authenticated requests.

## Useful scripts

```bash
npm run dev
npm run build
npm run test
```

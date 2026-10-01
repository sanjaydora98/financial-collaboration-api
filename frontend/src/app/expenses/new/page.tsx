"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { AppShell } from "@/components/app-shell";
import { Button, ErrorAlert, PageHeader } from "@/components/ui";
import { useAuth } from "@/components/auth-provider";
import { apiFetch } from "@/lib/api";
import { safeErrorMessage } from "@/lib/helpers";

export default function NewExpensePage() {
  const router = useRouter();
  const { selectedTeam } = useAuth();
  const [form, setForm] = useState({
    amount: "",
    currency: "USD",
    merchant: "",
    description: "",
    category: "Travel",
    incurred_on: new Date().toISOString().slice(0, 10),
  });
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedTeam?.id) {
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      const result = await apiFetch<{ expense: { id: number } }>(`/teams/${selectedTeam.id}/expenses`, {
        method: "POST",
        body: JSON.stringify({
          expense: {
            amount: Number(form.amount),
            currency: form.currency,
            merchant: form.merchant,
            description: form.description,
            category: form.category,
            incurred_on: form.incurred_on,
          },
        }),
      });

      router.push(`/expenses/${result.expense.id}`);
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <AppShell>
      <PageHeader title="New expense" subtitle="Draft a team expense." />

      {error ? <ErrorAlert message={error} /> : null}

      <form className="card form-card" onSubmit={handleSubmit}>
        <label>
          Amount
          <input
            type="number"
            min="0.01"
            step="0.01"
            value={form.amount}
            onChange={(event) => setForm((current) => ({ ...current, amount: event.target.value }))}
            required
          />
        </label>

        <label>
          Currency
          <input
            value={form.currency}
            onChange={(event) => setForm((current) => ({ ...current, currency: event.target.value }))}
            maxLength={3}
            required
          />
        </label>

        <label>
          Merchant
          <input
            value={form.merchant}
            onChange={(event) => setForm((current) => ({ ...current, merchant: event.target.value }))}
            required
          />
        </label>

        <label>
          Description
          <input
            value={form.description}
            onChange={(event) => setForm((current) => ({ ...current, description: event.target.value }))}
          />
        </label>

        <label>
          Category
          <input
            value={form.category}
            onChange={(event) => setForm((current) => ({ ...current, category: event.target.value }))}
          />
        </label>

        <label>
          Incurred on
          <input
            type="date"
            value={form.incurred_on}
            onChange={(event) => setForm((current) => ({ ...current, incurred_on: event.target.value }))}
            required
          />
        </label>

        <Button type="submit" disabled={submitting}>
          {submitting ? "Saving..." : "Create expense"}
        </Button>
      </form>
    </AppShell>
  );
}

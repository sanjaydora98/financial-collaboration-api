"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { Button, ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { useAuth } from "@/components/auth-provider";
import { apiFetch } from "@/lib/api";
import { formatCurrency, formatDate, safeErrorMessage } from "@/lib/helpers";
import type { Expense } from "@/lib/types";

export default function ExpenseDetailPage() {
  const params = useParams<{ id: string }>();
  const { selectedTeam } = useAuth();
  const [expense, setExpense] = useState<Expense | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState(false);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({
    amount: "",
    currency: "USD",
    merchant: "",
    description: "",
    category: "",
    incurred_on: "",
  });

  const loadExpense = useCallback(async () => {
    if (!selectedTeam?.id) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await apiFetch<{ expense: Expense }>(`/teams/${selectedTeam.id}/expenses/${params.id}`);
      setExpense(result.expense);
      setForm({
        amount: String(result.expense.amount),
        currency: result.expense.currency,
        merchant: result.expense.merchant,
        description: result.expense.description ?? "",
        category: result.expense.category ?? "",
        incurred_on: result.expense.incurred_on,
      });
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [params.id, selectedTeam]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadExpense();
    const handler = () => {
      void loadExpense();
    };
    window.addEventListener("team-realtime-update", handler);
    return () => window.removeEventListener("team-realtime-update", handler);
  }, [loadExpense]);

  async function handleUpdate(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!expense || !selectedTeam?.id) {
      return;
    }

    setUpdating(true);
    setError(null);

    try {
      await apiFetch<{ expense: Expense }>(`/teams/${selectedTeam.id}/expenses/${expense.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          expense: {
            amount: Number(form.amount),
            currency: form.currency,
            merchant: form.merchant,
            description: form.description,
            category: form.category,
            incurred_on: form.incurred_on,
          },
          lock_version: expense.lock_version,
        }),
      });
      setEditing(false);
      await loadExpense();
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setUpdating(false);
    }
  }

  async function handleSubmit() {
    if (!expense || !selectedTeam?.id) {
      return;
    }

    setUpdating(true);
    setError(null);

    try {
      await apiFetch(`/teams/${selectedTeam.id}/expenses/${expense.id}/submit`, { method: "POST" });
      await loadExpense();
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setUpdating(false);
    }
  }

  async function handleReimbursement() {
    if (!expense || !selectedTeam?.id) {
      return;
    }

    setUpdating(true);
    setError(null);

    try {
      await apiFetch(`/teams/${selectedTeam.id}/expenses/${expense.id}/reimbursement`, { method: "POST" });
      await loadExpense();
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setUpdating(false);
    }
  }

  if (loading) {
    return (
      <AppShell>
        <LoadingState label="Loading expense..." />
      </AppShell>
    );
  }

  if (!expense) {
    return (
      <AppShell>
        <div className="state-card">
          <h3>Expense not found</h3>
          <Link href="/expenses" className="button secondary">
            Back to expenses
          </Link>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell>
      <PageHeader
        title={`Expense #${expense.id}`}
        subtitle={expense.merchant}
        action={
          <Link href="/expenses" className="button secondary">
            Back to list
          </Link>
        }
      />

      {error ? <ErrorAlert message={error} /> : null}

      <div className="detail-grid">
        <div className="panel">
          <div className="panel-header">
            <h3>Summary</h3>
            <StatusBadge status={expense.status} />
          </div>
          <div className="key-value-grid">
            <p><strong>Amount</strong><span>{formatCurrency(expense.amount, expense.currency)}</span></p>
            <p><strong>Category</strong><span>{expense.category || "—"}</span></p>
            <p><strong>Description</strong><span>{expense.description || "—"}</span></p>
            <p><strong>Merchant</strong><span>{expense.merchant}</span></p>
            <p><strong>Incurred</strong><span>{formatDate(expense.incurred_on)}</span></p>
            <p><strong>Lock version</strong><span>{expense.lock_version}</span></p>
          </div>

          <div className="button-row">
            {expense.status === "draft" ? (
              <>
                <Button onClick={() => setEditing((current) => !current)} variant="secondary">
                  {editing ? "Cancel edit" : "Edit"}
                </Button>
                <Button onClick={() => void handleSubmit()} disabled={updating}>Submit</Button>
              </>
            ) : null}

            {expense.status === "approved" ? (
              <Button onClick={() => void handleReimbursement()} disabled={updating}>Create reimbursement</Button>
            ) : null}
          </div>
        </div>

        <div className="panel">
          <div className="panel-header">
            <h3>Audit</h3>
          </div>
          <div className="key-value-grid">
            <p><strong>Created</strong><span>{formatDate(expense.created_at)}</span></p>
            <p><strong>Updated</strong><span>{formatDate(expense.updated_at)}</span></p>
            <p><strong>Team</strong><span>{selectedTeam?.name || "—"}</span></p>
          </div>
        </div>
      </div>

      {editing ? (
        <form className="card form-card" onSubmit={handleUpdate}>
          <h3>Edit expense</h3>
          <label>
            Amount
            <input
              type="number"
              value={form.amount}
              onChange={(event) => setForm((current) => ({ ...current, amount: event.target.value }))}
            />
          </label>
          <label>
            Currency
            <input
              value={form.currency}
              onChange={(event) => setForm((current) => ({ ...current, currency: event.target.value }))}
            />
          </label>
          <label>
            Merchant
            <input
              value={form.merchant}
              onChange={(event) => setForm((current) => ({ ...current, merchant: event.target.value }))}
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
            />
          </label>
          <Button type="submit" disabled={updating}>{updating ? "Saving..." : "Save changes"}</Button>
        </form>
      ) : null}
    </AppShell>
  );
}

"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { useAuth } from "@/components/auth-provider";
import { apiFetch } from "@/lib/api";
import { formatCurrency, safeErrorMessage } from "@/lib/helpers";
import type { Expense } from "@/lib/types";

export default function ExpensesPage() {
  const { selectedTeam } = useAuth();
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [statusFilter, setStatusFilter] = useState("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    if (!selectedTeam?.id) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await apiFetch<{ expenses: Expense[] }>(`/teams/${selectedTeam.id}/expenses`);
      setExpenses(result.expenses ?? []);
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [selectedTeam]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadData();
    const handler = () => {
      void loadData();
    };
    window.addEventListener("team-realtime-update", handler);
    return () => window.removeEventListener("team-realtime-update", handler);
  }, [loadData]);

  const visibleExpenses = useMemo(() => {
    if (statusFilter === "all") {
      return expenses;
    }

    return expenses.filter((expense) => expense.status === statusFilter);
  }, [expenses, statusFilter]);

  return (
    <AppShell>
      <PageHeader
        title="Expenses"
        subtitle="Track and review team spend."
        action={
          <Link href="/expenses/new" className="button primary">
            New expense
          </Link>
        }
      />

      {error ? <ErrorAlert message={error} /> : null}

      <div className="toolbar">
        <label>
          Filter by status
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
            <option value="all">All</option>
            <option value="draft">Draft</option>
            <option value="submitted">Submitted</option>
            <option value="approved">Approved</option>
            <option value="rejected">Rejected</option>
            <option value="reimbursed">Reimbursed</option>
          </select>
        </label>
      </div>

      {loading ? (
        <LoadingState label="Loading expenses..." />
      ) : visibleExpenses.length === 0 ? (
        <div className="state-card">
          <h3>No expenses in this view</h3>
        </div>
      ) : (
        <div className="table-card">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Merchant</th>
                <th>Category</th>
                <th>Amount</th>
                <th>Status</th>
                <th>Updated</th>
              </tr>
            </thead>
            <tbody>
              {visibleExpenses.map((expense) => (
                <tr key={expense.id}>
                  <td>#{expense.id}</td>
                  <td>
                    <Link href={`/expenses/${expense.id}`} className="link-strong">
                      {expense.description || expense.merchant}
                    </Link>
                  </td>
                  <td>{expense.category || "—"}</td>
                  <td>{formatCurrency(expense.amount, expense.currency)}</td>
                  <td>
                    <StatusBadge status={expense.status} />
                  </td>
                  <td>{new Date(expense.updated_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </AppShell>
  );
}

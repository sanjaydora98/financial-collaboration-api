"use client";

import { useCallback, useEffect, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import { formatCurrency, safeErrorMessage } from "@/lib/helpers";
import type { Expense } from "@/lib/types";

export default function ReimbursementsPage() {
  const { selectedTeam } = useAuth();
  const [expenses, setExpenses] = useState<Expense[]>([]);
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
      setExpenses((result.expenses ?? []).filter((expense) => expense.status === "approved"));
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [selectedTeam]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadData();
  }, [loadData]);

  async function handleReimburse(expense: Expense) {
    if (!selectedTeam?.id) {
      return;
    }

    try {
      await apiFetch(`/teams/${selectedTeam.id}/expenses/${expense.id}/reimbursement`, { method: "POST" });
      await loadData();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  }

  return (
    <AppShell>
      <PageHeader title="Reimbursements" subtitle="Approved costs ready for reimbursement." />
      {error ? <ErrorAlert message={error} /> : null}

      {loading ? (
        <LoadingState label="Loading reimbursements..." />
      ) : expenses.length === 0 ? (
        <div className="state-card">
          <h3>No approved reimbursements available</h3>
        </div>
      ) : (
        <div className="stack-list">
          {expenses.map((expense) => (
            <div key={expense.id} className="panel list-panel">
              <div className="panel-header">
                <h3>{expense.description || expense.merchant}</h3>
                <StatusBadge status={expense.status} />
              </div>

              <div className="key-value-grid">
                <p><strong>Amount</strong><span>{formatCurrency(expense.amount, expense.currency)}</span></p>
                <p><strong>Merchant</strong><span>{expense.merchant}</span></p>
                <p><strong>Category</strong><span>{expense.category || "—"}</span></p>
              </div>

              <div className="button-row">
                <Button onClick={() => void handleReimburse(expense)}>Create reimbursement</Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </AppShell>
  );
}

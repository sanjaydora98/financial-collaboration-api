"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import { formatCurrency, safeErrorMessage } from "@/lib/helpers";
import type { Expense } from "@/lib/types";

export default function ApprovalsPage() {
  const { selectedTeam } = useAuth();
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rejectionReason, setRejectionReason] = useState<Record<number, string>>({});

  const loadData = useCallback(async () => {
    if (!selectedTeam?.id) {
      return;
    }

    try {
      setLoading(true);
      const result = await apiFetch<{ expenses: Expense[] }>(`/teams/${selectedTeam.id}/expenses`);
      setExpenses((result.expenses ?? []).filter((expense) => expense.status === "submitted"));
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [selectedTeam]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadData();
    const handleRealtimeUpdate = () => {
      void loadData();
    };
    window.addEventListener("team-realtime-update", handleRealtimeUpdate);
    return () => window.removeEventListener("team-realtime-update", handleRealtimeUpdate);
  }, [loadData]);

  async function handleDecision(expense: Expense, action: "approve" | "reject") {
    if (!selectedTeam?.id) {
      return;
    }

    try {
      const payload = {
        approval: {
          decision: action,
          rejection_reason: action === "reject" ? rejectionReason[expense.id] ?? "" : undefined,
        },
      };

      await apiFetch(`/teams/${selectedTeam.id}/expenses/${expense.id}/approval`, {
        method: "POST",
        body: JSON.stringify(payload),
      });
      await loadData();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  }

  const queue = useMemo(() => expenses, [expenses]);

  return (
    <AppShell>
      <PageHeader title="Approval queue" subtitle="Review submitted expenses for the active team." />
      {error ? <ErrorAlert message={error} /> : null}

      {loading ? (
        <LoadingState label="Loading approval queue..." />
      ) : queue.length === 0 ? (
        <div className="state-card">
          <h3>No pending approvals</h3>
        </div>
      ) : (
        <div className="stack-list">
          {queue.map((expense) => (
            <div key={expense.id} className="panel list-panel">
              <div className="panel-header">
                <h3>{expense.description || expense.merchant}</h3>
                <StatusBadge status={expense.status} />
              </div>
              <div className="key-value-grid">
                <p><strong>Amount</strong><span>{formatCurrency(expense.amount, expense.currency)}</span></p>
                <p><strong>Category</strong><span>{expense.category || "—"}</span></p>
                <p><strong>Merchant</strong><span>{expense.merchant}</span></p>
              </div>

              <div className="approval-form">
                <input
                  value={rejectionReason[expense.id] ?? ""}
                  onChange={(event) =>
                    setRejectionReason((current) => ({ ...current, [expense.id]: event.target.value }))
                  }
                  placeholder="Optional rejection reason"
                />
                <div className="button-row">
                  <Button onClick={() => void handleDecision(expense, "approve")}>Approve</Button>
                  <Button variant="secondary" onClick={() => void handleDecision(expense, "reject")}>
                    Reject
                  </Button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </AppShell>
  );
}

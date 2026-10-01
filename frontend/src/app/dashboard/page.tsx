"use client";

import Link from "next/link";
import { Plus } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { useAuth } from "@/components/auth-provider";
import { apiFetch } from "@/lib/api";
import { formatCurrency, safeErrorMessage } from "@/lib/helpers";
import type { Expense } from "@/lib/types";

function totalsByCurrency(expenses: Expense[]) {
  return expenses.reduce<Record<string, number>>((totals, expense) => {
    totals[expense.currency] = (totals[expense.currency] ?? 0) + Number(expense.amount);
    return totals;
  }, {});
}

export default function DashboardPage() {
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

  const summary = useMemo(() => {
    const submittedExpenses = expenses.filter((expense) => expense.status === "submitted");
    const reimbursedExpenses = expenses.filter((expense) => expense.status === "reimbursed");
    const counts = {
      total: expenses.length,
      submitted: submittedExpenses.length,
      approved: expenses.filter((expense) => expense.status === "approved").length,
      reimbursed: expenses.filter((expense) => expense.status === "reimbursed").length,
      totalSpend: totalsByCurrency(expenses),
      submittedSpend: totalsByCurrency(submittedExpenses),
      reimbursedSpend: totalsByCurrency(reimbursedExpenses),
    };

    return counts;
  }, [expenses]);

  return (
    <AppShell>
      <PageHeader
        title="Overview"
        subtitle={selectedTeam ? `A clear view of ${selectedTeam.name}` : "Select a team"}
        action={
          <Link href="/expenses/new" className="button primary">
            <Plus size={16} strokeWidth={2.2} aria-hidden="true" />
            New expense
          </Link>
        }
      />

      {error ? <ErrorAlert message={error} /> : null}

      {loading ? (
        <LoadingState label="Loading team overview..." />
      ) : (
        <>
          <div className="summary-grid">
            <div className="metric-card featured-metric">
              <span className="metric-label">Tracked spend</span>
              <div className="metric-amounts">
                {Object.entries(summary.totalSpend).length ? Object.entries(summary.totalSpend).map(([currency, amount]) => (
                  <strong key={currency}>{formatCurrency(amount, currency)}</strong>
                )) : <strong>—</strong>}
              </div>
              <small>{summary.total} expenses across the team</small>
            </div>
            <div className="metric-card">
              <span className="metric-label">Pending review</span>
              <strong>{summary.submitted}</strong>
              <small className="metric-detail">
                {Object.entries(summary.submittedSpend).length ? Object.entries(summary.submittedSpend).map(([currency, amount]) => (
                  <span key={currency}>{formatCurrency(amount, currency)}</span>
                )) : "No submitted spend"}
              </small>
            </div>
            <div className="metric-card">
              <span className="metric-label">Approved</span>
              <strong>{summary.approved}</strong>
              <small>Ready for reimbursement</small>
            </div>
            <div className="metric-card">
              <span className="metric-label">Reimbursed</span>
              <div className="metric-amounts">
                {Object.entries(summary.reimbursedSpend).length ? Object.entries(summary.reimbursedSpend).map(([currency, amount]) => (
                  <strong key={currency}>{formatCurrency(amount, currency)}</strong>
                )) : <strong>—</strong>}
              </div>
              <small>{summary.reimbursed} completed payments</small>
            </div>
          </div>

          <div className="dashboard-grid">
            <section className="panel recent-panel">
              <div className="panel-header">
                <h3>Recent activity</h3>
                <Link href="/expenses">View all</Link>
              </div>

              {expenses.length === 0 ? (
                <p className="muted">No expense activity yet.</p>
              ) : (
                <div className="list-stack">
                  {expenses.slice(0, 6).map((expense) => (
                    <div key={expense.id} className="list-row">
                      <span className="activity-marker" aria-hidden="true">{expense.merchant.slice(0, 1)}</span>
                      <div>
                        <Link href={`/expenses/${expense.id}`} className="link-strong">
                          {expense.description || expense.merchant}
                        </Link>
                        <p className="muted">{expense.merchant}</p>
                      </div>
                      <div className="row-meta">
                        <strong>{formatCurrency(expense.amount, expense.currency)}</strong>
                        <StatusBadge status={expense.status} />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <section className="panel pending-panel">
              <div className="panel-header">
                <div>
                  <span className="eyebrow">ACTION REQUIRED</span>
                  <h3>Pending approvals</h3>
                </div>
                <span className="count-badge">{summary.submitted}</span>
              </div>
              {expenses.filter((expense) => expense.status === "submitted").length === 0 ? (
                <p className="muted">Nothing needs attention right now.</p>
              ) : (
                <div className="list-stack">
                  {expenses.filter((expense) => expense.status === "submitted").slice(0, 4).map((expense) => (
                    <Link key={expense.id} href={`/expenses/${expense.id}`} className="pending-row">
                      <span>{expense.description || expense.merchant}</span>
                      <strong>{formatCurrency(expense.amount, expense.currency)}</strong>
                    </Link>
                  ))}
                </div>
              )}
              <Link href="/approvals" className="button secondary pending-link">Open approval queue</Link>
            </section>
          </div>
        </>
      )}
    </AppShell>
  );
}

"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { Button, ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { useAuth } from "@/components/auth-provider";
import { apiFetch } from "@/lib/api";
import { formatCurrency, formatDate, safeErrorMessage, titleCase } from "@/lib/helpers";
import type { AuditLogEntry, Expense } from "@/lib/types";

const HIDDEN_AUDIT_FIELDS = new Set(["id", "lock_version"]);

function auditEventLabel(event: AuditLogEntry) {
  const labels: Record<string, string> = {
    create: "Expense created",
    update: "Expense updated",
    delete: "Expense deleted",
    submitted: "Expense submitted",
    approved: "Expense approved",
    rejected: "Expense rejected",
    reimbursement_initiated: "Reimbursement initiated",
    reimbursement_paid: "Reimbursement paid",
    reimbursement_failed: "Reimbursement failed",
    import_accepted: "Imported transaction accepted",
  };
  return labels[event.event_type] ?? titleCase(event.event_type);
}

function auditChanges(event: AuditLogEntry) {
  const before = event.change_data.before ?? {};
  const after = event.change_data.after ?? {};
  return Array.from(new Set([...Object.keys(before), ...Object.keys(after)]))
    .filter((field) => !field.endsWith("_id") && !field.endsWith("_at") && !HIDDEN_AUDIT_FIELDS.has(field))
    .filter((field) => JSON.stringify(before[field]) !== JSON.stringify(after[field]))
    .map((field) => ({ field, before: before[field], after: after[field] }));
}

function auditValue(field: string, value: unknown, currency: string) {
  if (value === null || value === undefined || value === "") return "—";
  if (field === "amount" && Number.isFinite(Number(value))) return formatCurrency(Number(value), currency);
  if (field.endsWith("_status") || field === "status" || field === "approval_stage" || field === "decision") {
    return titleCase(String(value));
  }
  if (field === "incurred_on" && typeof value === "string") return new Date(`${value}T00:00:00`).toLocaleDateString();
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

export default function ExpenseDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { selectedTeam } = useAuth();
  const [expense, setExpense] = useState<Expense | null>(null);
  const [auditLogs, setAuditLogs] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState(false);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({
    amount: "",
    currency: "INR",
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
      const result = await apiFetch<{ expense: Expense; audit_logs?: AuditLogEntry[] }>(`/teams/${selectedTeam.id}/expenses/${params.id}`);
      setExpense(result.expense);
      setAuditLogs(result.audit_logs ?? []);
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

  async function handleDelete() {
    if (!expense || !selectedTeam?.id) {
      return;
    }

    const confirmed = window.confirm("Delete this expense? This action cannot be undone.");
    if (!confirmed) {
      return;
    }

    setUpdating(true);
    setError(null);

    try {
      await apiFetch(`/teams/${selectedTeam.id}/expenses/${expense.id}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ lock_version: expense.lock_version }),
      });
      router.push("/expenses");
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

  const canDeleteExpense = expense.status === "draft" && (
    selectedTeam?.membership?.role === "admin" ||
    selectedTeam?.membership?.id === expense.creator_membership_id
  );

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
                {canDeleteExpense ? (
                  <Button onClick={() => void handleDelete()} variant="secondary" disabled={updating}>Delete</Button>
                ) : null}
              </>
            ) : null}

            {expense.status === "approved" ? (
              <Button onClick={() => void handleReimbursement()} disabled={updating}>Create reimbursement</Button>
            ) : null}
          </div>
        </div>

        <section className="panel audit-panel">
          <div className="panel-header">
            <h3>Audit history</h3>
          </div>
          {auditLogs.length === 0 ? (
            <p className="muted">No audit events available.</p>
          ) : (
            <ol className="audit-timeline">
              {auditLogs.map((event, index) => {
                const actor = event.actor?.name || event.actor?.email || (event.actor_type === "system" ? "System" : "Unknown user");
                const changes = auditChanges(event);
                return (
                  <li className="audit-event" key={`${event.created_at}-${event.event_type}-${index}`}>
                    <span className="audit-marker" aria-hidden="true" />
                    <div className="audit-event-content">
                      <div className="audit-event-header">
                        <strong>{auditEventLabel(event)}</strong>
                        <time dateTime={event.created_at}>{formatDate(event.created_at)}</time>
                      </div>
                      <p className="audit-actor">By {actor}</p>
                      {changes.length > 0 ? (
                        <ul className="audit-changes">
                          {changes.map(({ field, before, after }) => (
                            <li key={field}>
                              <strong>{titleCase(field)}:</strong>
                              <span>{auditValue(field, before, expense.currency)}</span>
                              <span className="audit-arrow" aria-label="changed to">→</span>
                              <span>{auditValue(field, after, expense.currency)}</span>
                            </li>
                          ))}
                        </ul>
                      ) : null}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
          <p className="audit-team">Team: {selectedTeam?.name || "—"}</p>
        </section>
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

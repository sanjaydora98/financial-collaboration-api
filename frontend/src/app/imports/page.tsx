"use client";

import { useCallback, useEffect, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import { safeErrorMessage } from "@/lib/helpers";
import type { ImportRecord } from "@/lib/types";

export default function ImportsPage() {
  const { selectedTeam } = useAuth();
  const [imports, setImports] = useState<ImportRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [provider, setProvider] = useState("csv");
  const [idempotencyKey, setIdempotencyKey] = useState("demo-import");
  const [transactions, setTransactions] = useState(
    `[
      {"external_account_ref":"acct-100","external_transaction_id":"txn-1","amount":45.5,"currency":"INR","merchant":"Coffee House","description":"Team coffee","category":"Meals","transaction_date":"2026-10-01"}
    ]`,
  );

  const loadData = useCallback(async () => {
    if (!selectedTeam?.id) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await apiFetch<{ imports: ImportRecord[] }>(`/teams/${selectedTeam.id}/imports`);
      setImports(result.imports ?? []);
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

  async function submitImport(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedTeam?.id) {
      return;
    }

    try {
      const parsed = JSON.parse(transactions);
      await apiFetch(`/teams/${selectedTeam.id}/imports`, {
        method: "POST",
        body: JSON.stringify({
          import: {
            provider,
            idempotency_key: idempotencyKey,
            transactions: parsed,
          },
        }),
      });

      setIdempotencyKey(`demo-import-${window.crypto.randomUUID()}`);
      await loadData();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  }

  return (
    <AppShell>
      <PageHeader title="Imports" subtitle="Submit external transaction batches for review." />
      {error ? <ErrorAlert message={error} /> : null}

      <div className="two-column-grid">
        <form className="card form-card" onSubmit={submitImport}>
          <h3>Request import</h3>

          <label>
            Provider
            <input value={provider} onChange={(event) => setProvider(event.target.value)} />
          </label>

          <label>
            Idempotency key
            <input value={idempotencyKey} onChange={(event) => setIdempotencyKey(event.target.value)} />
          </label>

          <label>
            Transactions JSON
            <textarea
              value={transactions}
              onChange={(event) => setTransactions(event.target.value)}
              rows={10}
            />
          </label>

          <Button type="submit">Submit import</Button>
        </form>

        <div className="panel">
          <div className="panel-header">
            <h3>Recent imports</h3>
          </div>

          {loading ? (
            <LoadingState label="Loading imports..." />
          ) : imports.length === 0 ? (
            <div className="state-card">
              <p>No imports created yet.</p>
            </div>
          ) : (
            <div className="list-stack">
              {imports.map((record) => (
                <div key={record.id} className="list-row compact-row">
                  <div>
                    <strong>#{record.id}</strong>
                    <p className="muted">{record.provider}</p>
                  </div>
                  <div className="row-meta">
                    <StatusBadge status={record.status} />
                    <span className="muted">{record.imported_transaction_count} items</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </AppShell>
  );
}

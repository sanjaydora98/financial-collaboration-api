"use client";

import { useCallback, useEffect, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, LoadingState, PageHeader, StatusBadge } from "@/components/ui";
import { ApiError, apiFetch } from "@/lib/api";
import { formatCurrency, safeErrorMessage, titleCase } from "@/lib/helpers";
import type { ImportRecord, ImportedTransaction } from "@/lib/types";

export default function ImportedTransactionsPage() {
  const { selectedTeam } = useAuth();
  const [imports, setImports] = useState<ImportRecord[]>([]);
  const [transactions, setTransactions] = useState<ImportedTransaction[]>([]);
  const [selectedImportId, setSelectedImportId] = useState<number | null>(null);
  const [selectedIds, setSelectedIds] = useState<number[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const [results, setResults] = useState<Array<{ id: number; result: string }>>([]);

  const loadData = useCallback(async () => {
    if (!selectedTeam?.id) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const importsResult = await apiFetch<{ imports: ImportRecord[] }>(`/teams/${selectedTeam.id}/imports`);
      const nextImports = importsResult.imports ?? [];
      setImports(nextImports);

      if (!selectedImportId && nextImports[0]) {
        setSelectedImportId(nextImports[0].id);
      }

      if (selectedImportId) {
        const transactionsResult = await apiFetch<{ imported_transactions: ImportedTransaction[] }>(
          `/teams/${selectedTeam.id}/imports/${selectedImportId}/imported_transactions`,
        );
        setTransactions(transactionsResult.imported_transactions ?? []);
      }
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [selectedImportId, selectedTeam]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadData();
  }, [loadData]);

  function toggleSelected(id: number) {
    setSelectedIds((current) =>
      current.includes(id) ? current.filter((value) => value !== id) : [...current, id],
    );
  }

  async function bulkReview(action: "accept" | "reject") {
    if (!selectedTeam?.id || selectedIds.length === 0) {
      return;
    }

    const rejectionReason = action === "reject" ? window.prompt("Enter rejection reason") : null;
    if (action === "reject" && !rejectionReason?.trim()) {
      return;
    }

    setReviewing(true);
    setError(null);
    try {
      const payload: Record<string, unknown> = {
        ids: selectedIds,
        action,
      };

      if (action === "reject") {
        payload.rejection_reason = rejectionReason ?? "";
      }

      const result = await apiFetch<{ results: Array<{ id: number; result: string }> }>(
        `/teams/${selectedTeam.id}/imported_transactions/bulk_review`,
        {
          method: "POST",
          body: JSON.stringify(payload),
        },
      );

      setResults(result.results ?? []);
      setSelectedIds([]);
      await loadData();
    } catch (err) {
      const outcomes = err instanceof ApiError
        ? (err.details as { results?: Array<{ id: number; result: string }> } | undefined)?.results
        : undefined;

      if (outcomes) {
        setResults(outcomes);
        setSelectedIds([]);
        await loadData();
        setError("Bulk review finished with conflicts or validation errors. See the per-item results.");
      } else {
        setError(safeErrorMessage(err));
      }
    } finally {
      setReviewing(false);
    }
  }

  return (
    <AppShell>
      <PageHeader title="Imported transactions" subtitle="Review pending imported transactions." />
      {error ? <ErrorAlert message={error} /> : null}

      {results.length > 0 ? (
        <div className="state-card">
          <h3>Bulk review results</h3>
          <ul className="results-list">
            {results.map((result) => (
              <li key={result.id}>
                #{result.id}: {titleCase(result.result)}
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="toolbar">
        <label>
          Import
          <select
            value={selectedImportId ?? ""}
            onChange={(event) => setSelectedImportId(Number(event.target.value) || null)}
          >
            {imports.map((item) => (
              <option key={item.id} value={item.id}>
                #{item.id} ({item.status})
              </option>
            ))}
          </select>
        </label>

        <div className="button-row">
          <Button onClick={() => void bulkReview("accept")} disabled={selectedIds.length === 0 || reviewing}>Bulk Accept</Button>
          <Button variant="secondary" onClick={() => void bulkReview("reject")} disabled={selectedIds.length === 0 || reviewing}>
            Bulk Reject
          </Button>
        </div>
      </div>

      {loading ? (
        <LoadingState label="Loading imported transactions..." />
      ) : transactions.length === 0 ? (
        <div className="state-card">
          <h3>No imported transactions to review</h3>
        </div>
      ) : (
        <div className="table-card">
          <table>
            <thead>
              <tr>
                <th>Select</th>
                <th>ID</th>
                <th>Description</th>
                <th>Amount</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((transaction) => (
                <tr key={transaction.id}>
                  <td>
                    <input
                      type="checkbox"
                      checked={selectedIds.includes(transaction.id)}
                      onChange={() => toggleSelected(transaction.id)}
                    />
                  </td>
                  <td>#{transaction.id}</td>
                  <td>{transaction.description || transaction.merchant || "—"}</td>
                  <td>{formatCurrency(transaction.amount, transaction.currency)}</td>
                  <td>
                    <StatusBadge status={transaction.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </AppShell>
  );
}

"use client";

import { useCallback, useEffect, useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { ErrorAlert, LoadingState, PageHeader } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import { roleLabel, safeErrorMessage } from "@/lib/helpers";
import type { TeamMembership } from "@/lib/types";

export default function TeamMembersPage() {
  const { selectedTeam } = useAuth();
  const [memberships, setMemberships] = useState<TeamMembership[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    if (!selectedTeam?.id) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await apiFetch<{ memberships: TeamMembership[] }>(`/teams/${selectedTeam.id}/memberships`);
      setMemberships(result.memberships ?? []);
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

  return (
    <AppShell>
      <PageHeader title="Team members" subtitle="Review membership access and workflow roles." />
      {error ? <ErrorAlert message={error} /> : null}

      {loading ? (
        <LoadingState label="Loading team members..." />
      ) : memberships.length === 0 ? (
        <div className="state-card">
          <h3>No team members found</h3>
        </div>
      ) : (
        <div className="table-card">
          <table>
            <thead>
              <tr>
                <th>User</th>
                <th>Role</th>
                <th>Approval stage</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {memberships.map((membership) => (
                <tr key={membership.id}>
                  <td>#{membership.user_id}</td>
                  <td>{roleLabel(membership.role)}</td>
                  <td>{membership.approval_stage || "—"}</td>
                  <td>{membership.active ? "Active" : "Inactive"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </AppShell>
  );
}

"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, PageHeader } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import { safeErrorMessage } from "@/lib/helpers";
import type { Team } from "@/lib/types";

export default function JoinTeamPage() {
  const router = useRouter();
  const { refreshSession } = useAuth();
  const [joinCode, setJoinCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);

    try {
      await apiFetch<{ team: Team }>('/teams/join', {
        method: 'POST',
        body: JSON.stringify({ team: { join_code: joinCode } }),
      });
      await refreshSession();
      router.push('/dashboard');
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <AppShell>
      <PageHeader title="Join team" subtitle="Use a team code to join an existing workspace." />
      {error ? <ErrorAlert message={error} /> : null}

      <form className="card form-card" onSubmit={handleSubmit}>
        <label>
          Team code
          <input
            value={joinCode}
            onChange={(event) => setJoinCode(event.target.value.trim().toLowerCase())}
            placeholder="northstar-studio"
            required
          />
        </label>

        <Button type="submit" disabled={submitting || !joinCode}>
          {submitting ? 'Joining...' : 'Join team'}
        </Button>
      </form>
    </AppShell>
  );
}

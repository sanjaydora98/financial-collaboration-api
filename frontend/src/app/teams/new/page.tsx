"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, PageHeader } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import type { Team } from "@/lib/types";
import { safeErrorMessage } from "@/lib/helpers";

export default function CreateTeamPage() {
  const router = useRouter();
  const { refreshSession } = useAuth();
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);

    try {
      await apiFetch<{ team: Team }>('/teams', {
        method: 'POST',
        body: JSON.stringify({ team: { name, slug } }),
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
      <PageHeader title="Create team" subtitle="Start a new workspace and invite others with your team code." />
      {error ? <ErrorAlert message={error} /> : null}

      <form className="card form-card" onSubmit={handleSubmit}>
        <label>
          Team name
          <input value={name} onChange={(event) => setName(event.target.value)} required />
        </label>

        <label>
          Team code
          <input
            value={slug}
            onChange={(event) => setSlug(event.target.value.trim().toLowerCase())}
            placeholder="northstar-studio"
            required
          />
        </label>

        <Button type="submit" disabled={submitting || !name || !slug}>
          {submitting ? 'Creating...' : 'Create team'}
        </Button>
      </form>
    </AppShell>
  );
}

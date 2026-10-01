"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { useAuth } from "@/components/auth-provider";
import { Button, ErrorAlert, LoadingState } from "@/components/ui";
import { safeErrorMessage } from "@/lib/helpers";

export default function RegisterPage() {
  const router = useRouter();
  const { register, user, loading } = useAuth();
  const [form, setForm] = useState({
    name: "",
    email: "",
    password: "",
    password_confirmation: "",
  });
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!loading && user) {
      router.replace("/dashboard");
    }
  }, [loading, router, user]);

  if (loading || user) {
    return <LoadingState label="Checking your account..." />;
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await register(form);
      router.replace("/dashboard");
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-page">
      <form className="auth-card" onSubmit={handleSubmit}>
        <h1>Create account</h1>
        <p className="muted">Set up a new workspace member.</p>

        {error ? <ErrorAlert message={error} /> : null}

        <label>
          Full name
          <input
            value={form.name}
            onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))}
            placeholder="Alex Morgan"
            required
          />
        </label>

        <label>
          Email
          <input
            type="email"
            value={form.email}
            onChange={(event) => setForm((current) => ({ ...current, email: event.target.value }))}
            placeholder="you@example.com"
            required
          />
        </label>

        <label>
          Password
          <input
            type="password"
            value={form.password}
            onChange={(event) => setForm((current) => ({ ...current, password: event.target.value }))}
            placeholder="Password"
            required
          />
        </label>

        <label>
          Password confirmation
          <input
            type="password"
            value={form.password_confirmation}
            onChange={(event) =>
              setForm((current) => ({ ...current, password_confirmation: event.target.value }))
            }
            placeholder="Repeat password"
            required
          />
        </label>

        <Button type="submit" disabled={submitting}>
          {submitting ? "Creating account..." : "Register"}
        </Button>

        <p className="inline-link">
          Already have an account? <Link href="/login">Log in</Link>
        </p>
      </form>
    </div>
  );
}

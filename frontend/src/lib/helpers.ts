import type { ApiErrorPayload } from "@/lib/types";

export function formatCurrency(amount: number, currency = "USD") {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    maximumFractionDigits: 2,
  }).format(amount);
}

export function formatDate(value?: string | null) {
  if (!value) {
    return "—";
  }

  return new Date(value).toLocaleString();
}

export function safeErrorMessage(error: unknown): string {
  if (typeof error === "string") {
    return error;
  }

  if (error instanceof Error) {
    return error.message;
  }

  const payload = error as ApiErrorPayload | null;
  return payload?.error?.message ?? "Something went wrong.";
}

export function statusTone(status?: string | null) {
  switch (status) {
    case "draft":
      return "neutral";
    case "submitted":
      return "info";
    case "approved":
      return "success";
    case "rejected":
      return "danger";
    case "reimbursed":
      return "success";
    case "pending":
      return "warning";
    case "failed":
      return "danger";
    default:
      return "neutral";
  }
}

export function roleLabel(role?: string | null) {
  switch (role) {
    case "admin":
      return "Admin";
    case "approver":
      return "Approver";
    case "creator":
      return "Creator";
    case "viewer":
      return "Viewer";
    default:
      return "Member";
  }
}

export function titleCase(value?: string | null) {
  if (!value) {
    return "—";
  }

  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

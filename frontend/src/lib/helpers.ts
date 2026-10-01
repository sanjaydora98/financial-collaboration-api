import type { ApiErrorPayload } from "@/lib/types";

export function formatCurrency(amount: number, currency = "INR") {
  const normalizedCurrency = (currency ?? "INR").toString().toUpperCase();
  const finalCurrency = normalizedCurrency === "USD" ? "INR" : normalizedCurrency || "INR";

  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: finalCurrency,
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
    const details = (error as Error & { details?: unknown }).details as ApiErrorPayload | undefined;
    const validationDetails = details?.error?.details;
    if (validationDetails) {
      const messages = Object.entries(validationDetails).flatMap(([field, value]) => {
        const fieldMessages = Array.isArray(value) ? value : [value];
        return fieldMessages
          .filter((message): message is string => typeof message === "string" && message.trim().length > 0)
          .map((message) => `${titleCase(field)}: ${message}`);
      });
      if (messages.length > 0) return messages.join(" ");
    }
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

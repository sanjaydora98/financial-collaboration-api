import type { ApiErrorPayload, AuthPayload, Team, User } from "@/lib/types";

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3000";

const AUTH_TOKEN_KEY = "expense-collab-token";

export class ApiError extends Error {
  status: number;
  details?: unknown;

  constructor(status: number, message: string, details?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.details = details;
  }
}

export function getStoredToken(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  return localStorage.getItem(AUTH_TOKEN_KEY);
}

export function setStoredToken(token: string) {
  if (typeof window !== "undefined") {
    localStorage.setItem(AUTH_TOKEN_KEY, token);
  }
}

export function clearStoredToken() {
  if (typeof window !== "undefined") {
    localStorage.removeItem(AUTH_TOKEN_KEY);
    localStorage.removeItem("selected-team-id");
  }
}

export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = getStoredToken();
  const headers = new Headers(init.headers ?? {});

  if (!(init.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }

  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers,
    cache: "no-store",
  });

  if (response.status === 204) {
    return null as T;
  }

  const contentType = response.headers.get("content-type") ?? "";
  const data = contentType.includes("application/json")
    ? ((await response.json()) as ApiErrorPayload | T)
    : null;

  if (!response.ok) {
    const payload = data as ApiErrorPayload | null;
    const message = payload?.error?.message ?? "Request failed.";
    throw new ApiError(response.status, message, payload);
  }

  return (data ?? ({} as T)) as T;
}

export async function registerUser(payload: {
  email: string;
  password: string;
  name: string;
  password_confirmation: string;
}) {
  return apiFetch<AuthPayload>("/auth/register", {
    method: "POST",
    body: JSON.stringify({ user: payload }),
  });
}

export async function loginUser(payload: { email: string; password: string }) {
  return apiFetch<AuthPayload>("/auth/login", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export async function logoutUser() {
  return apiFetch<void>("/auth/logout", { method: "DELETE" });
}

export async function fetchCurrentUser() {
  return apiFetch<{ user: User }>("/auth/me");
}

export async function fetchTeams() {
  return apiFetch<{ teams: Team[] }>("/teams");
}

export async function fetchActionCableTicket() {
  return apiFetch<{ ticket: string }>("/auth/cable_ticket", { method: "POST" });
}

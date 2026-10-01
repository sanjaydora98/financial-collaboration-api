import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiFetchMock, authState } = vi.hoisted(() => ({
  apiFetchMock: vi.fn(),
  authState: {
    value: {
      selectedTeam: { id: 1, name: "Northstar", membership: { id: 10, role: "approver" } },
    },
  },
}));

vi.mock("@/components/app-shell", () => ({
  AppShell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

vi.mock("@/components/auth-provider", () => ({
  useAuth: () => authState.value,
}));

vi.mock("@/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/api")>();
  return { ...actual, apiFetch: apiFetchMock };
});

import ApprovalsPage from "./page";

function baseExpense(overrides: Record<string, unknown> = {}) {
  return {
    id: 1,
    team_id: 1,
    creator_membership_id: 5,
    member_membership_id: 5,
    amount: 100,
    currency: "USD",
    merchant: "Acme",
    description: "Travel",
    category: "Travel",
    incurred_on: "2026-10-01",
    status: "submitted",
    lock_version: 0,
    created_at: "2026-10-01T10:00:00Z",
    updated_at: "2026-10-01T10:00:00Z",
    approvals: [],
    ...overrides,
  };
}

describe("Approvals queue action state", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    authState.value = {
      selectedTeam: { id: 1, name: "Northstar", membership: { id: 10, role: "approver" } },
    };
  });

  it("hides the Approve button when the current user's manager stage is already approved", async () => {
    apiFetchMock.mockResolvedValue({
      expenses: [
        baseExpense({
          approvals: [
            { id: 1, step: 1, stage: "manager", approver_membership_id: 10, status: "approved", acted_at: "2026-10-01T11:00:00Z" },
            { id: 2, step: 2, stage: "finance", approver_membership_id: 20, status: "pending", acted_at: null },
          ],
        }),
      ],
    });

    render(<ApprovalsPage />);

    await screen.findByRole("heading", { name: "Travel" });
    expect(screen.queryByRole("button", { name: "Approve" })).not.toBeInTheDocument();
    expect(screen.getByText(/Your stage \(Manager\): Approved/)).toBeInTheDocument();
  });

  it("shows the Approve button when the current user's stage is pending", async () => {
    apiFetchMock.mockResolvedValue({
      expenses: [
        baseExpense({
          approvals: [
            { id: 1, step: 1, stage: "manager", approver_membership_id: 10, status: "pending", acted_at: null },
            { id: 2, step: 2, stage: "finance", approver_membership_id: 20, status: "queued", acted_at: null },
          ],
        }),
      ],
    });

    render(<ApprovalsPage />);

    expect(await screen.findByRole("button", { name: "Approve" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Reject" })).toBeInTheDocument();
  });

  it("lets Finance approve once Finance is the current pending stage after Manager approval", async () => {
    authState.value = {
      selectedTeam: { id: 1, name: "Northstar", membership: { id: 20, role: "approver" } },
    };
    apiFetchMock.mockResolvedValue({
      expenses: [
        baseExpense({
          approvals: [
            { id: 1, step: 1, stage: "manager", approver_membership_id: 10, status: "approved", acted_at: "2026-10-01T11:00:00Z" },
            { id: 2, step: 2, stage: "finance", approver_membership_id: 20, status: "pending", acted_at: null },
          ],
        }),
      ],
    });

    render(<ApprovalsPage />);

    expect(await screen.findByRole("button", { name: "Approve" })).toBeInTheDocument();
  });

  it("shows no approval action once the current user's stage has been rejected", async () => {
    apiFetchMock.mockResolvedValue({
      expenses: [
        baseExpense({
          approvals: [
            { id: 1, step: 1, stage: "manager", approver_membership_id: 10, status: "rejected", acted_at: "2026-10-01T11:00:00Z", rejection_reason: "Missing receipt" },
            { id: 2, step: 2, stage: "finance", approver_membership_id: 20, status: "skipped", acted_at: "2026-10-01T11:00:00Z" },
          ],
        }),
      ],
    });

    render(<ApprovalsPage />);

    await screen.findByRole("heading", { name: "Travel" });
    expect(screen.queryByRole("button", { name: "Approve" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Reject" })).not.toBeInTheDocument();
    expect(screen.getByText(/Your stage \(Manager\): Rejected/)).toBeInTheDocument();
  });

  it("shows no approval action while the current user's stage is still queued", async () => {
    authState.value = {
      selectedTeam: { id: 1, name: "Northstar", membership: { id: 20, role: "approver" } },
    };
    apiFetchMock.mockResolvedValue({
      expenses: [
        baseExpense({
          approvals: [
            { id: 1, step: 1, stage: "manager", approver_membership_id: 10, status: "pending", acted_at: null },
            { id: 2, step: 2, stage: "finance", approver_membership_id: 20, status: "queued", acted_at: null },
          ],
        }),
      ],
    });

    render(<ApprovalsPage />);

    await screen.findByRole("heading", { name: "Travel" });
    expect(screen.queryByRole("button", { name: "Approve" })).not.toBeInTheDocument();
    expect(screen.getByText(/Your stage \(Finance\): Queued/)).toBeInTheDocument();
  });
});

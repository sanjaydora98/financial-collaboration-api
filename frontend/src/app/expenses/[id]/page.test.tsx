import { render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiFetchMock, selectedTeam } = vi.hoisted(() => ({
  apiFetchMock: vi.fn(),
  selectedTeam: { id: 1, name: "Northstar", membership: { id: 5, role: "creator" } },
}));

vi.mock("@/components/app-shell", () => ({
  AppShell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

vi.mock("@/components/auth-provider", () => ({
  useAuth: () => ({ selectedTeam }),
}));

vi.mock("next/navigation", () => ({
  useParams: () => ({ id: "17" }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock("@/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/api")>();
  return { ...actual, apiFetch: apiFetchMock };
});

import ExpenseDetailPage from "./page";

describe("Expense detail audit history", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    apiFetchMock.mockResolvedValue({
      expense: {
        id: 17,
        team_id: 1,
        creator_membership_id: 5,
        member_membership_id: 5,
        amount: 15000,
        currency: "INR",
        merchant: "Client travel",
        description: "Client travel - Chennai",
        category: "Travel",
        incurred_on: "2026-10-01",
        status: "submitted",
        lock_version: 1,
        created_at: "2026-10-01T10:00:00Z",
        updated_at: "2026-10-01T11:00:00Z",
      },
      audit_logs: [
        {
          category: "crud",
          event_type: "update",
          actor_type: "user",
          actor: { name: "Avery Admin", email: "demo.admin@example.com" },
          created_at: "2026-10-01T11:00:00Z",
          change_data: {
            before: { amount: 10000, description: "Client travel" },
            after: { amount: 15000, description: "Client travel - Chennai" },
          },
        },
        {
          category: "crud",
          event_type: "create",
          actor_type: "user",
          actor: { name: "Avery Admin", email: "demo.admin@example.com" },
          created_at: "2026-10-01T10:00:00Z",
          change_data: { before: {}, after: { merchant: "Client travel" } },
        },
        {
          category: "crud",
          event_type: "delete",
          actor_type: "user",
          actor: { name: "Avery Admin", email: "demo.admin@example.com" },
          created_at: "2026-10-01T09:00:00Z",
          change_data: { before: {}, after: { deleted_at: "2026-10-01T09:00:00Z" } },
        },
        {
          category: "workflow",
          event_type: "submitted",
          actor_type: "system",
          actor: { name: "System", email: null },
          created_at: "2026-10-01T08:00:00Z",
          change_data: {
            before: { expense_status: "draft" },
            after: { expense_status: "submitted", manager_approval_status: "pending" },
          },
        },
      ],
    });
  });

  it("renders changed fields with old and new values, actor, and timestamp", async () => {
    render(<ExpenseDetailPage />);

    const audit = await screen.findByRole("heading", { name: "Audit history" });
    const panel = audit.closest(".audit-panel");
    expect(panel).not.toBeNull();
    expect(within(panel as HTMLElement).getByText("Expense updated")).toBeInTheDocument();
    expect(within(panel as HTMLElement).getAllByText("By Avery Admin")).toHaveLength(3);
    const amountChange = within(panel as HTMLElement).getByText("Amount:").parentElement;
    expect(amountChange).toHaveTextContent("₹10,000.00");
    expect(amountChange).toHaveTextContent("₹15,000.00");
    const descriptionChange = within(panel as HTMLElement).getByText("Description:").parentElement;
    expect(descriptionChange).toHaveTextContent("Client travel");
    expect(descriptionChange).toHaveTextContent("Client travel - Chennai");
    expect(within(panel as HTMLElement).getAllByRole("time")[0]).toHaveAttribute(
      "datetime",
      "2026-10-01T11:00:00Z",
    );
  });

  it("labels create, delete, and workflow audit events", async () => {
    render(<ExpenseDetailPage />);
    const panel = (await screen.findByRole("heading", { name: "Audit history" })).closest(".audit-panel");
    expect(panel).not.toBeNull();
    expect(within(panel as HTMLElement).getByText("Expense created")).toBeInTheDocument();
    expect(within(panel as HTMLElement).getByText("Expense deleted")).toBeInTheDocument();
    expect(within(panel as HTMLElement).getByText("Expense submitted")).toBeInTheDocument();
    expect(within(panel as HTMLElement).queryByText("Id:")).not.toBeInTheDocument();
    const statusChange = within(panel as HTMLElement).getByText("Expense Status:").closest("li");
    expect(statusChange).toHaveTextContent("Draft");
    expect(statusChange).toHaveTextContent("Submitted");
    expect(within(panel as HTMLElement).getByText("By System")).toBeInTheDocument();
  });

  it("shows delete for a draft expense when the current user can delete it", async () => {
    apiFetchMock.mockResolvedValueOnce({
      expense: {
        id: 17,
        team_id: 1,
        creator_membership_id: 5,
        member_membership_id: 5,
        amount: 15000,
        currency: "INR",
        merchant: "Client travel",
        description: "Client travel - Chennai",
        category: "Travel",
        incurred_on: "2026-10-01",
        status: "draft",
        lock_version: 1,
        created_at: "2026-10-01T10:00:00Z",
        updated_at: "2026-10-01T11:00:00Z",
      },
      audit_logs: [],
    });

    render(<ExpenseDetailPage />);
    expect(await screen.findByRole("button", { name: "Delete" })).toBeInTheDocument();
  });
});
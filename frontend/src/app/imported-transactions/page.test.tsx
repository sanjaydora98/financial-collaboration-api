import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiFetchMock, mockTeam } = vi.hoisted(() => ({
  apiFetchMock: vi.fn(),
  mockTeam: { id: 1, name: "Team" },
}));

vi.mock("@/components/app-shell", () => ({
  AppShell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

vi.mock("@/components/auth-provider", () => ({
  useAuth: () => ({ selectedTeam: mockTeam }),
}));

vi.mock("@/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/api")>();
  return { ...actual, apiFetch: apiFetchMock };
});

import { ApiError } from "@/lib/api";
import ImportedTransactionsPage from "./page";

describe("Imported transactions page", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    apiFetchMock.mockImplementation((path: string) => {
      if (path.endsWith("/imports")) {
        return Promise.resolve({ imports: [{ id: 10, status: "completed" }] });
      }

      if (path.endsWith("/imported_transactions")) {
        return Promise.resolve({
          imported_transactions: [{
            id: 1,
            description: "Coffee",
            amount: 4.5,
            currency: "USD",
            status: "pending",
          }],
        });
      }

      return Promise.reject(new ApiError(409, "Request failed.", {
        results: [
          { id: 1, result: "accepted" },
          { id: 2, result: "conflict" },
        ],
      }));
    });
  });

  it("shows each outcome when bulk review returns a partial conflict", async () => {
    const user = userEvent.setup();
    render(<ImportedTransactionsPage />);

    await user.click(await screen.findByRole("checkbox"));
    await user.click(screen.getByRole("button", { name: "Bulk Accept" }));

    expect(await screen.findByText("Bulk review finished with conflicts or validation errors. See the per-item results.")).toBeInTheDocument();
    expect(screen.getByText("#1: Accepted")).toBeInTheDocument();
    expect(screen.getByText("#2: Conflict")).toBeInTheDocument();
  });
});
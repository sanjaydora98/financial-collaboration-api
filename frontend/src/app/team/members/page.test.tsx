import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiFetchMock, authState } = vi.hoisted(() => ({
  apiFetchMock: vi.fn(),
  authState: {
    value: {
      user: { id: 3, email: "admin@example.com", name: "Admin User" },
      selectedTeam: { id: 1, name: "Northstar", join_code: undefined as string | undefined, membership: { role: "admin" } },
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

import { ApiError } from "@/lib/api";
import TeamMembersPage from "./page";

const targetMembership = {
  id: 42,
  public_id: "b0b7e2d2-2c58-4638-9ee2-8b7f82cba202",
  user_id: 84,
  user: { name: "Jordan Lee", email: "jordan@example.com" },
  role: "viewer" as const,
  approval_stage: null,
  active: true,
  status: "active" as const,
};

type MembershipFixture = Omit<typeof targetMembership, "active" | "status"> & {
  active: boolean;
  status: "active" | "inactive";
};

let currentMemberships: MembershipFixture[];

function setupApi() {
  currentMemberships = [{ ...targetMembership }];
  apiFetchMock.mockImplementation(async (_path: string, init: RequestInit = {}) => {
    if (!init.method) return { memberships: currentMemberships };
    if (init.method === "PATCH") {
      const attributes = JSON.parse(String(init.body)).membership;
      currentMemberships = currentMemberships.map((membership) => ({
        ...membership,
        ...attributes,
        status: attributes.active === false ? "inactive" : "active",
      }));
      return { membership: currentMemberships[0] };
    }
    if (init.method === "DELETE") {
      currentMemberships = currentMemberships.map((membership) => ({ ...membership, active: false, status: "inactive" }));
      return { membership: currentMemberships[0] };
    }
    throw new Error(`Unexpected request method: ${init.method}`);
  });
}

describe("Team members page", () => {
  beforeEach(() => {
    apiFetchMock.mockReset();
    authState.value = {
      user: { id: 3, email: "admin@example.com", name: "Admin User" },
      selectedTeam: { id: 1, name: "Northstar", join_code: undefined, membership: { role: "admin" } },
    };
    setupApi();
  });

  it("shows member name and email without rendering internal IDs", async () => {
    const { container } = render(<TeamMembersPage />);

    expect(await screen.findByText("Jordan Lee")).toBeInTheDocument();
    expect(screen.getByText("jordan@example.com")).toBeInTheDocument();
    expect(container).not.toHaveTextContent("#42");
    expect(container).not.toHaveTextContent("#84");
    expect(container).not.toHaveTextContent(/\b42\b|\b84\b/);
  });

  it("shows management controls to admins but not non-admins", async () => {
    const { unmount } = render(<TeamMembersPage />);
    expect(await screen.findByRole("button", { name: "Edit Jordan Lee" })).toBeInTheDocument();

    unmount();
    authState.value.selectedTeam.membership.role = "viewer";
    render(<TeamMembersPage />);
    await screen.findByText("Jordan Lee");
    expect(screen.queryByRole("button", { name: "Edit Jordan Lee" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Deactivate Jordan Lee" })).not.toBeInTheDocument();
  });

  it("lets an admin copy the join code to invite new members without creating accounts directly", async () => {
    authState.value = {
      user: { id: 3, email: "admin@example.com", name: "Admin User" },
      selectedTeam: { id: 1, name: "Northstar", join_code: "northstar-studio", membership: { role: "admin" } },
    };
    const user = userEvent.setup();
    render(<TeamMembersPage />);

    const inviteButton = await screen.findByRole("button", { name: "Invite member (copy join code)" });
    await user.click(inviteButton);

    expect(await screen.findByText(/Join code "northstar-studio" copied/)).toBeInTheDocument();
    expect(apiFetchMock.mock.calls.every((call) => call[0] !== "/auth/register")).toBe(true);
  });

  it("hides the invite action for non-admins", async () => {
    authState.value = {
      user: { id: 3, email: "admin@example.com", name: "Admin User" },
      selectedTeam: { id: 1, name: "Northstar", join_code: "northstar-studio", membership: { role: "viewer" } },
    };
    render(<TeamMembersPage />);

    await screen.findByText("Jordan Lee");
    expect(screen.queryByRole("button", { name: "Invite member (copy join code)" })).not.toBeInTheDocument();
  });

  it("submits the selected approver manager stage through the public UUID and refreshes the list", async () => {
    const user = userEvent.setup();
    render(<TeamMembersPage />);
    await user.click(await screen.findByRole("button", { name: "Edit Jordan Lee" }));

    await user.selectOptions(screen.getByLabelText("Role"), "approver");
    await user.selectOptions(screen.getByLabelText("Approval stage"), "manager");
    await user.click(screen.getByRole("button", { name: "Save changes" }));

    expect(await screen.findByText("Approver")).toBeInTheDocument();
    expect(await screen.findByText("Manager")).toBeInTheDocument();
    expect(await screen.findByText("Jordan Lee updated.")).toBeInTheDocument();
    expect(apiFetchMock).toHaveBeenCalledWith(
      "/teams/1/memberships/b0b7e2d2-2c58-4638-9ee2-8b7f82cba202",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ membership: { role: "approver", approval_stage: "manager" } }),
      }),
    );
    expect(apiFetchMock.mock.calls.filter((call) => !call[1]?.method)).toHaveLength(2);
  });

  it("shows backend update conflicts in the editor", async () => {
    apiFetchMock.mockImplementation(async (_path: string, init: RequestInit = {}) => {
      if (!init.method) return { memberships: [targetMembership] };
      return Promise.reject(new ApiError(409, "The approval stage is occupied."));
    });
    const user = userEvent.setup();
    render(<TeamMembersPage />);
    await user.click(await screen.findByRole("button", { name: "Edit Jordan Lee" }));
    await user.click(screen.getByRole("button", { name: "Save changes" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("The approval stage is occupied.");
  });

  it("renders structured Rails validation details when the response has no message", async () => {
    apiFetchMock.mockImplementation(async (_path: string, init: RequestInit = {}) => {
      if (!init.method) return { memberships: [targetMembership] };
      return Promise.reject(new ApiError(422, "Request failed.", {
        error: { details: { approval_stage: ["is not valid for this role"] } },
      }));
    });
    const user = userEvent.setup();
    render(<TeamMembersPage />);
    await user.click(await screen.findByRole("button", { name: "Edit Jordan Lee" }));
    await user.selectOptions(screen.getByLabelText("Role"), "approver");
    await user.selectOptions(screen.getByLabelText("Approval stage"), "manager");
    await user.click(screen.getByRole("button", { name: "Save changes" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Approval Stage: is not valid for this role");
  });

  it("reactivates inactive members through the existing backend update route", async () => {
    currentMemberships = [{ ...targetMembership, active: false, status: "inactive" }];
    const user = userEvent.setup();
    render(<TeamMembersPage />);
    await user.click(await screen.findByRole("button", { name: "Activate Jordan Lee" }));

    expect(await screen.findByText("Jordan Lee activated.")).toBeInTheDocument();
    expect(apiFetchMock).toHaveBeenCalledWith(
      "/teams/1/memberships/b0b7e2d2-2c58-4638-9ee2-8b7f82cba202",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ membership: { active: true } }),
      }),
    );
    expect(await screen.findByText("Active")).toBeInTheDocument();
  });
});
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const { authState } = vi.hoisted(() => ({
  authState: {
    value: {
      user: { id: 1, email: "creator@example.com", name: "Casey Creator" },
      teams: [{ id: 1, name: "Northstar", slug: "northstar", join_code: "northstar", membership: { role: "admin" } }],
      selectedTeam: { id: 1, name: "Northstar", slug: "northstar", join_code: "northstar", membership: { role: "admin" } },
      loading: false,
      logout: vi.fn(),
      selectTeam: vi.fn(),
    },
  },
}));

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard",
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

vi.mock("@/components/auth-provider", () => ({
  useAuth: () => authState.value,
}));

vi.mock("@/hooks/use-team-realtime", () => ({
  useTeamRealtime: () => undefined,
}));

import { AppShell } from "./app-shell";

describe("AppShell", () => {
  it("shows the signed-in user's current role so a team creator immediately sees Admin", () => {
    authState.value = {
      ...authState.value,
      selectedTeam: { ...authState.value.selectedTeam, membership: { role: "admin" } },
    };

    render(
      <AppShell>
        <div>content</div>
      </AppShell>
    );

    expect(screen.getByTestId("current-role-badge")).toHaveTextContent("Your role: Admin");
  });

  it("reflects a viewer's role for a team they joined by code", () => {
    authState.value = {
      ...authState.value,
      selectedTeam: { ...authState.value.selectedTeam, membership: { role: "viewer" } },
    };

    render(
      <AppShell>
        <div>content</div>
      </AppShell>
    );

    expect(screen.getByTestId("current-role-badge")).toHaveTextContent("Your role: Viewer");
  });
});

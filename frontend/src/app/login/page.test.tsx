import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

const loginMock = vi.fn();

vi.mock("@/components/auth-provider", () => ({
  useAuth: () => ({
    user: null,
    loading: false,
    login: loginMock,
    register: vi.fn(),
    logout: vi.fn(),
    selectTeam: vi.fn(),
    refreshSession: vi.fn(),
    teams: [],
    selectedTeam: null,
  }),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({
    replace: vi.fn(),
  }),
}));

describe("Login page", () => {
  it("submits credentials and shows errors for failed login", async () => {
    loginMock.mockRejectedValueOnce(new Error("Email or password is invalid."));

    const user = userEvent.setup();
    render(<LoginPage />);

    await user.type(screen.getByLabelText(/email/i), "user@example.com");
    await user.type(screen.getByLabelText(/password/i), "secret123");
    await user.click(screen.getByRole("button", { name: /log in/i }));

    expect(await screen.findByText("Email or password is invalid.")).toBeInTheDocument();
  });
});

// this import is intentionally below the mock setup to align with Vitest hoisting
import LoginPage from "./page";

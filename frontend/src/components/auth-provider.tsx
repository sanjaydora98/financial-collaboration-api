"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

import {
  clearStoredToken,
  fetchCurrentUser,
  fetchTeams,
  getStoredToken,
  loginUser,
  logoutUser,
  registerUser,
  setStoredToken,
} from "@/lib/api";
import type { Team, User } from "@/lib/types";

type AuthContextValue = {
  user: User | null;
  teams: Team[];
  selectedTeam: Team | null;
  loading: boolean;
  login: (payload: { email: string; password: string }) => Promise<void>;
  register: (payload: {
    email: string;
    password: string;
    name: string;
    password_confirmation: string;
  }) => Promise<void>;
  logout: () => Promise<void>;
  selectTeam: (teamId: number) => void;
  refreshSession: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [teams, setTeams] = useState<Team[]>([]);
  const [selectedTeamId, setSelectedTeamId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshSession = useCallback(async () => {
    const token = getStoredToken();

    if (!token) {
      setUser(null);
      setTeams([]);
      setSelectedTeamId(null);
      setLoading(false);
      return;
    }

    try {
      const currentUserResult = await fetchCurrentUser();
      setUser(currentUserResult.user);

      const teamResult = await fetchTeams();
      const nextTeams = teamResult.teams ?? [];
      setTeams(nextTeams);

      const savedId = Number(localStorage.getItem("selected-team-id") ?? "");
      const fallback = nextTeams.find((team) => team.id === savedId)
        ? savedId
        : nextTeams[0]?.id ?? null;
      setSelectedTeamId(fallback);
      if (fallback) {
        localStorage.setItem("selected-team-id", String(fallback));
      }
    } catch {
      clearStoredToken();
      setUser(null);
      setTeams([]);
      setSelectedTeamId(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void refreshSession();
  }, [refreshSession]);

  const selectTeam = useCallback((teamId: number) => {
    setSelectedTeamId(teamId);
    if (typeof window !== "undefined") {
      localStorage.setItem("selected-team-id", String(teamId));
    }
  }, []);

  const login = useCallback(async (payload: { email: string; password: string }) => {
    const result = await loginUser(payload);
    setStoredToken(result.token);
    await refreshSession();
  }, [refreshSession]);

  const register = useCallback(async (payload: {
    email: string;
    password: string;
    name: string;
    password_confirmation: string;
  }) => {
    const result = await registerUser(payload);
    setStoredToken(result.token);
    await refreshSession();
  }, [refreshSession]);

  const logout = useCallback(async () => {
    try {
      await logoutUser();
    } catch {
      // intentionally ignore logout failures to keep the session state safe
    }

    clearStoredToken();
    setUser(null);
    setTeams([]);
    setSelectedTeamId(null);
  }, []);

  const selectedTeam = useMemo(
    () => teams.find((team) => team.id === selectedTeamId) ?? teams[0] ?? null,
    [selectedTeamId, teams],
  );

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      teams,
      selectedTeam,
      loading,
      login,
      register,
      logout,
      selectTeam,
      refreshSession,
    }),
    [loading, login, logout, refreshSession, register, selectTeam, selectedTeam, teams, user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }

  return context;
}

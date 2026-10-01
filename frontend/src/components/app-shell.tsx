"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import {
  ArrowDownToLine,
  ClipboardCheck,
  FileClock,
  LayoutDashboard,
  LogOut,
  Receipt,
  Users,
  WalletCards,
} from "lucide-react";

import { useAuth } from "@/components/auth-provider";
import { Button, LoadingState } from "@/components/ui";
import { useTeamRealtime } from "@/hooks/use-team-realtime";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/expenses", label: "Expenses", icon: Receipt },
  { href: "/approvals", label: "Approvals", icon: ClipboardCheck },
  { href: "/reimbursements", label: "Reimbursements", icon: WalletCards },
  { href: "/imports", label: "Imports", icon: ArrowDownToLine },
  { href: "/imported-transactions", label: "Imported Transactions", icon: FileClock },
  { href: "/team/members", label: "Team Members", icon: Users },
];

function Sidebar({ pathname }: { pathname: string }) {
  return (
    <aside className="sidebar">
      <Link href="/dashboard" className="brand-block" aria-label="Expense Collab home">
        <span className="brand-mark" aria-hidden="true">EC</span>
        <span className="brand-name">Expense Collab</span>
      </Link>

      <p className="nav-caption">WORKSPACE</p>
      <nav className="nav-list" aria-label="Main navigation">
        {navItems.map((item) => {
          const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`nav-item ${active ? "active" : ""}`}
              aria-current={active ? "page" : undefined}
            >
              <span className="nav-symbol" aria-hidden="true"><Icon size={17} strokeWidth={1.8} /></span>
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>
      <div className="sidebar-footer">
        <span className="status-indicator" aria-hidden="true" />
        <span>All systems operational</span>
      </div>
    </aside>
  );
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { user, teams, selectedTeam, loading, logout, selectTeam } = useAuth();
  useTeamRealtime(selectedTeam?.id ?? null);

  useEffect(() => {
    if (!loading && !user) {
      router.replace("/login");
    }
  }, [loading, router, user]);

  if (loading) {
    return <LoadingState label="Loading account..." />;
  }

  if (!user) {
    return <LoadingState label="Redirecting to sign in..." />;
  }

  return (
    <div className="app-shell">
      <Sidebar pathname={pathname} />

      <main className="content-panel">
        <header className="topbar">
          <div className="topbar-left">
            <div className="team-selector-box">
              <label htmlFor="team-selector">WORKSPACE</label>
              <select
                id="team-selector"
                aria-label="Current team"
                value={selectedTeam?.id ?? ""}
                onChange={(event) => {
                  const nextId = Number(event.target.value);
                  if (!Number.isNaN(nextId)) {
                    selectTeam(nextId);
                  }
                }}
              >
                {teams.length === 0 ? (
                  <option value="">No teams</option>
                ) : (
                  teams.map((team) => (
                    <option key={team.id} value={team.id}>
                      {team.name}
                    </option>
                  ))
                )}
              </select>
            </div>
          </div>

          <div className="topbar-right">
            <span className="user-name">{user.name}</span>
            <span className="user-avatar" aria-hidden="true">
              {user.name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase()}
            </span>
            <Button
              variant="secondary"
              aria-label="Log out"
              onClick={() => {
                void logout();
                router.push("/login");
              }}
            >
              <LogOut size={15} strokeWidth={1.9} aria-hidden="true" />
              Log out
            </Button>
          </div>
        </header>

        <div className="page-content">{children}</div>
      </main>
    </div>
  );
}

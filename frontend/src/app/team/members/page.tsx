"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Pencil, UserCheck, UserRoundX } from "lucide-react";

import { AppShell } from "@/components/app-shell";
import { useAuth } from "@/components/auth-provider";
import { Button, EmptyState, ErrorAlert, LoadingState, PageHeader } from "@/components/ui";
import { apiFetch } from "@/lib/api";
import { roleLabel, safeErrorMessage, titleCase } from "@/lib/helpers";
import type { TeamMembership } from "@/lib/types";

type MembershipRole = TeamMembership["role"];

function memberName(membership: TeamMembership) {
  return membership.user.name?.trim() || membership.user.email;
}

function memberInitials(membership: TeamMembership) {
  return memberName(membership)
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

function MembershipEditorDialog({
  membership,
  saving,
  onClose,
  onSave,
}: {
  membership: TeamMembership;
  saving: boolean;
  onClose: () => void;
  onSave: (attributes: { role: MembershipRole; approval_stage: string | null }) => Promise<void>;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [role, setRole] = useState<MembershipRole>(membership.role);
  const [approvalStage, setApprovalStage] = useState(membership.approval_stage ?? "");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
    dialog.querySelector("select")?.focus();
    return () => {
      if (dialog.open && typeof dialog.close === "function") dialog.close();
      else dialog.removeAttribute("open");
    };
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const formData = new FormData(event.currentTarget);
    const submittedRole = formData.get("role");
    const submittedStage = formData.get("approval_stage");
    try {
      await onSave({
        role: typeof submittedRole === "string" ? submittedRole as MembershipRole : role,
        approval_stage: typeof submittedStage === "string" && submittedStage ? submittedStage : null,
      });
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  }

  function changeRole(nextRole: MembershipRole) {
    setRole(nextRole);
    if (nextRole !== "approver" && nextRole !== "admin") setApprovalStage("");
  }

  return (
    <dialog
      ref={dialogRef}
      className="modal-dialog membership-dialog"
      aria-labelledby="membership-dialog-title"
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <form className="modal-content" onSubmit={submit}>
        <header className="modal-header">
          <div>
            <p className="eyebrow">MEMBERSHIP SETTINGS</p>
            <h2 id="membership-dialog-title">Manage {memberName(membership)}</h2>
            <p className="muted">{membership.user.email}</p>
          </div>
          <button type="button" className="icon-button" aria-label="Close dialog" onClick={onClose}>×</button>
        </header>

        {error ? <ErrorAlert message={error} /> : null}

        <div className="modal-fields">
          <label>
            Role
            <select name="role" value={role} onChange={(event) => changeRole(event.target.value as MembershipRole)}>
              <option value="admin">Admin</option>
              <option value="approver">Approver</option>
              <option value="viewer">Viewer</option>
              <option value="creator">Creator</option>
            </select>
          </label>

          {role === "approver" || role === "admin" ? (
            <label>
              Approval stage
              <select
                name="approval_stage"
                value={approvalStage}
                required={role === "approver"}
                onChange={(event) => setApprovalStage(event.target.value)}
              >
                {role === "admin" ? <option value="">No approval stage</option> : null}
                <option value="manager">Manager</option>
                <option value="finance">Finance</option>
              </select>
            </label>
          ) : null}
        </div>

        <footer className="modal-actions">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={saving}>{saving ? "Saving..." : "Save changes"}</Button>
        </footer>
      </form>
    </dialog>
  );
}

export default function TeamMembersPage() {
  const { selectedTeam, user } = useAuth();
  const [memberships, setMemberships] = useState<TeamMembership[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editingMembership, setEditingMembership] = useState<TeamMembership | null>(null);
  const [saving, setSaving] = useState(false);
  const [busyMembershipId, setBusyMembershipId] = useState<string | null>(null);
  const canManage = selectedTeam?.membership?.role === "admin";

  const loadData = useCallback(async () => {
    if (!selectedTeam?.id) {
      setMemberships([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await apiFetch<{ memberships: TeamMembership[] }>(`/teams/${selectedTeam.id}/memberships`);
      setMemberships(result.memberships ?? []);
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [selectedTeam]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadData();
  }, [loadData]);

  async function updateMembership(attributes: { role: MembershipRole; approval_stage: string | null }) {
    if (!selectedTeam?.id || !editingMembership) return;
    setSaving(true);
    setError(null);
    setNotice(null);
    try {
      await apiFetch(`/teams/${selectedTeam.id}/memberships/${editingMembership.public_id}`, {
        method: "PATCH",
        body: JSON.stringify({ membership: attributes }),
      });
      await loadData();
      setNotice(`${memberName(editingMembership)} updated.`);
    } finally {
      setSaving(false);
    }
  }

  async function changeActivation(membership: TeamMembership) {
    if (!selectedTeam?.id) return;
    if (membership.active && !window.confirm(`Deactivate ${memberName(membership)}?`)) return;

    setBusyMembershipId(membership.public_id);
    setError(null);
    setNotice(null);
    try {
      const path = `/teams/${selectedTeam.id}/memberships/${membership.public_id}`;
      await apiFetch(path, membership.active
        ? { method: "DELETE" }
        : { method: "PATCH", body: JSON.stringify({ membership: { active: true } }) });
      await loadData();
      setNotice(`${memberName(membership)} ${membership.active ? "deactivated" : "activated"}.`);
    } catch (err) {
      setError(safeErrorMessage(err));
    } finally {
      setBusyMembershipId(null);
    }
  }

  async function copyJoinCode() {
    if (!selectedTeam?.join_code) return;
    setError(null);
    try {
      if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(selectedTeam.join_code);
      }
      setNotice(`Join code "${selectedTeam.join_code}" copied. Share it so new members can join from Join team.`);
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  }

  return (
    <AppShell>
      <PageHeader
        title="Team members"
        subtitle="Review membership access and workflow roles."
        action={
          canManage && selectedTeam?.join_code ? (
            <Button variant="secondary" onClick={() => void copyJoinCode()}>
              Invite member (copy join code)
            </Button>
          ) : null
        }
      />
      {error ? <ErrorAlert message={error} /> : null}
      {notice ? <p className="success-notice" role="status">{notice}</p> : null}

      {loading ? (
        <LoadingState label="Loading team members..." />
      ) : memberships.length === 0 ? (
        <EmptyState title="No team members found" />
      ) : (
        <div className="table-card member-table-card">
          <table>
            <thead>
              <tr>
                <th>Member</th>
                <th>Role</th>
                <th>Approval Stage</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {memberships.map((membership) => (
                <tr key={membership.public_id}>
                  <td data-label="Member">
                    <div className="member-identity">
                      <span className="member-avatar" aria-hidden="true">{memberInitials(membership)}</span>
                      <span className="member-copy">
                        <strong>{memberName(membership)}</strong>
                        <span>{membership.user.email}</span>
                      </span>
                    </div>
                  </td>
                  <td data-label="Role">{roleLabel(membership.role)}</td>
                  <td data-label="Approval Stage">
                    {titleCase(membership.approval_stage)}
                  </td>
                  <td data-label="Status">
                    <span className={`member-status ${membership.active ? "active" : "inactive"}`}>
                      <span aria-hidden="true" />
                      {membership.active ? "Active" : "Inactive"}
                    </span>
                  </td>
                  <td data-label="Actions">
                    {canManage && user?.email.toLowerCase() !== membership.user.email.toLowerCase() ? (
                      <div className="member-actions">
                        <Button
                          variant="secondary"
                          className="member-action"
                          aria-label={`Edit ${memberName(membership)}`}
                          onClick={() => {
                            setError(null);
                            setNotice(null);
                            setEditingMembership(membership);
                          }}
                        >
                          <Pencil size={14} aria-hidden="true" />
                          Edit
                        </Button>
                        <Button
                          variant="secondary"
                          className="member-action"
                          aria-label={`${membership.active ? "Deactivate" : "Activate"} ${memberName(membership)}`}
                          disabled={busyMembershipId === membership.public_id}
                          onClick={() => void changeActivation(membership)}
                        >
                          {membership.active
                            ? <><UserRoundX size={15} aria-hidden="true" />Deactivate</>
                            : <><UserCheck size={15} aria-hidden="true" />Activate</>}
                        </Button>
                      </div>
                    ) : <span className="muted">—</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {editingMembership ? (
        <MembershipEditorDialog
          key={editingMembership.public_id}
          membership={editingMembership}
          saving={saving}
          onClose={() => setEditingMembership(null)}
          onSave={updateMembership}
        />
      ) : null}
    </AppShell>
  );
}

import type { ReactNode } from "react";

export function LoadingState({ label = "Loading..." }: { label?: string }) {
  return (
    <div className="state-card loading-state" role="status" aria-live="polite">
      <span className="loading-mark" aria-hidden="true" />
      <span>{label}</span>
      <span className="loading-bars" aria-hidden="true"><i /><i /><i /></span>
    </div>
  );
}

export function ErrorAlert({ message }: { message: string }) {
  return <div className="state-card error-box" role="alert"><strong>Error</strong><p>{message}</p></div>;
}

export function EmptyState({ title, description }: { title: string; description?: string }) {
  return (
    <div className="state-card empty-state" role="status">
      <h3>{title}</h3>
      {description ? <p>{description}</p> : null}
    </div>
  );
}

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <section className={`card ${className}`.trim()}>{children}</section>;
}

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: ReactNode;
}) {
  return (
    <div className="page-header">
      <div>
        <h1>{title}</h1>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>
      {action ? <div>{action}</div> : null}
    </div>
  );
}

export function StatusBadge({ status }: { status?: string | null }) {
  const normalizedStatus = status?.toLowerCase() ?? "unknown";
  const tone = ["approved", "paid", "reimbursed", "accepted"].includes(normalizedStatus)
    ? "success"
    : ["rejected", "failed", "cancelled"].includes(normalizedStatus)
      ? "danger"
      : ["submitted", "pending", "processing", "running"].includes(normalizedStatus)
        ? "warning"
        : "neutral";
  return <span className={`status-badge ${tone}`}>{status ?? "unknown"}</span>;
}

export function Button({
  children,
  variant = "primary",
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "danger";
}) {
  const { className = "", ...buttonProps } = props;
  return <button className={`button ${variant} ${className}`.trim()} {...buttonProps}>{children}</button>;
}

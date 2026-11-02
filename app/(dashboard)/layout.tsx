import "./dashboard.css";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <main className="dash">{children}</main>;
}

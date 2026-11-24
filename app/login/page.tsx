import { Suspense } from "react";
import LoginForm from "@/components/login-form";

export default function LoginPage() {
  return <Suspense fallback={<main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">กำลังโหลด...</main>}><LoginForm /></Suspense>;
}

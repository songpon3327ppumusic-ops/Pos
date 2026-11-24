"use client";
import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signIn(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError("");
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      const next = params.get("next");
      router.replace(next && next.startsWith("/") && !next.startsWith("//") ? next : "/");
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "เข้าสู่ระบบไม่สำเร็จ");
    } finally { setBusy(false); }
  }

  return <main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">
    <form onSubmit={signIn} className="w-full max-w-md rounded-3xl border border-slate-100 bg-white p-8 shadow-soft">
      <div className="mb-7 flex items-center gap-3"><div className="rounded-xl bg-emerald-600 p-3 text-white">SF</div><div><h1 className="text-2xl font-extrabold">Store<span className="text-emerald-600">Flow</span></h1><p className="text-xs text-slate-400">STORE MANAGEMENT SUITE</p></div></div>
      <h2 className="text-xl font-bold">เข้าสู่ระบบ</h2><p className="mb-6 mt-1 text-sm text-slate-500">ลงชื่อเข้าใช้บัญชีร้านค้าของคุณ</p>
      <label className="mb-4 block text-sm font-medium">อีเมล<input required type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="you@example.com"/></label>
      <label className="mb-4 block text-sm font-medium">รหัสผ่าน<input required type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="••••••••"/></label>
      {error && <p role="alert" className="mb-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
      <button disabled={busy} className="w-full rounded-xl bg-emerald-600 py-3 font-semibold text-white disabled:opacity-60">{busy?"กำลังเข้าสู่ระบบ...":"เข้าสู่ระบบ"}</button>
      <p className="mt-5 text-center text-xs text-slate-400">บัญชีผู้ใช้จัดการผ่าน Supabase Auth</p>
    </form>
  </main>;
}
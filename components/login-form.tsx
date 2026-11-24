"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  async function submit(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      const supabase = createClient();
      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email, password, options: { data: { full_name: name }, emailRedirectTo: `${window.location.origin}/Pos/` }
        });
        if (error) throw error;
        if (!data.session) {
          setNotice("สมัครสมาชิกแล้ว กรุณายืนยันอีเมลจากกล่องจดหมาย จากนั้นกลับมาเข้าสู่ระบบ");
          setMode("login");
          return;
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      }
      window.location.assign("/Pos/");
    } catch (e) {
      setError(e instanceof Error ? e.message : "ดำเนินการไม่สำเร็จ");
    } finally { setBusy(false); }
  }

  return <main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">
    <form onSubmit={submit} className="w-full max-w-md rounded-3xl border border-slate-100 bg-white p-8 shadow-soft">
      <div className="mb-7 flex items-center gap-3"><div className="rounded-xl bg-emerald-600 p-3 text-white">SF</div><div><h1 className="text-2xl font-extrabold">Store<span className="text-emerald-600">Flow</span></h1><p className="text-xs text-slate-400">STORE MANAGEMENT SUITE</p></div></div>
      <h2 className="text-xl font-bold">{mode === "login" ? "เข้าสู่ระบบ" : "สร้างบัญชีเจ้าของร้าน"}</h2>
      <p className="mb-6 mt-1 text-sm text-slate-500">{mode === "login" ? "ลงชื่อเข้าใช้บัญชีร้านค้าของคุณ" : "บัญชีแรกจะได้รับสิทธิ์ Owner ของ StoreFlow"}</p>
      {mode === "signup" && <label className="mb-4 block text-sm font-medium">ชื่อที่แสดง<input required value={name} onChange={e=>setName(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="ชื่อเจ้าของร้าน"/></label>}
      <label className="mb-4 block text-sm font-medium">อีเมล<input required type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="you@example.com"/></label>
      <label className="mb-4 block text-sm font-medium">รหัสผ่าน<input required minLength={8} type="password" autoComplete={mode === "login" ? "current-password" : "new-password"} value={password} onChange={e=>setPassword(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="อย่างน้อย 8 ตัวอักษร"/></label>
      {error && <p role="alert" className="mb-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
      {notice && <p role="status" className="mb-4 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
      <button disabled={busy} className="w-full rounded-xl bg-emerald-600 py-3 font-semibold text-white disabled:opacity-60">{busy ? "กำลังดำเนินการ..." : mode === "login" ? "เข้าสู่ระบบ" : "สมัครสมาชิก"}</button>
      <button type="button" onClick={()=>{setMode(mode === "login" ? "signup" : "login");setError("");setNotice("");}} className="mt-4 w-full rounded-xl border border-slate-200 py-3 text-sm font-semibold text-slate-600">{mode === "login" ? "ยังไม่มีบัญชี? สมัครเจ้าของร้าน" : "มีบัญชีอยู่แล้ว? เข้าสู่ระบบ"}</button>
      <p className="mt-5 text-center text-xs leading-5 text-slate-400">บัญชีและรหัสผ่านจัดการผ่าน Supabase Auth<br/>บัญชีแรกจะผูกกับร้าน StoreFlow โดยอัตโนมัติ</p>
    </form>
  </main>;
}

"use client";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Mail as MailIcon } from "lucide-react";

type SignupRole = "owner" | "cashier";

export default function LoginPage() {
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [signupRole, setSignupRole] = useState<SignupRole>("owner");
  const [name, setName] = useState("");
  const [storeName, setStoreName] = useState("");
  const [inviteCode, setInviteCode] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [verificationEmail, setVerificationEmail] = useState("");
  const [verificationPending, setVerificationPending] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);
  const [resendBusy, setResendBusy] = useState(false);

  useEffect(() => {
    if (resendCooldown <= 0) return;
    const timer = window.setTimeout(() => setResendCooldown(v => Math.max(0, v - 1)), 1000);
    return () => window.clearTimeout(timer);
  }, [resendCooldown]);

  async function resendConfirmation() {
    if (!verificationEmail || resendCooldown > 0 || resendBusy) return;
    setResendBusy(true); setError(""); setNotice("");
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.resend({ type: "signup", email: verificationEmail, options: { emailRedirectTo: `${window.location.origin}/Pos/` } });
      if (error) throw error;
      setNotice("ส่งอีเมลยืนยันอีกครั้งแล้ว กรุณาตรวจสอบกล่องจดหมายและโฟลเดอร์ Spam");
      setResendCooldown(60);
    } catch (e) {
      const message = e instanceof Error ? e.message : "ส่งอีเมลไม่สำเร็จ";
      const wait = message.match(/after (\d+) seconds/i);
      if (wait) setResendCooldown(Math.max(1, Number(wait[1])));
      setError(message);
    } finally { setResendBusy(false); }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      const supabase = createClient();
      if (mode === "signup") {
        if (signupRole === "owner" && storeName.trim().length < 2) throw new Error("กรุณากรอกชื่อร้านค้าอย่างน้อย 2 ตัวอักษร");
        if (signupRole === "cashier" && !inviteCode.trim()) throw new Error("กรุณากรอกรหัสเชิญร้าน");
        const { data, error } = await supabase.auth.signUp({
          email, password,
          options: {
            data: {
              full_name: name.trim(),
              onboarding_role: signupRole,
              ...(signupRole === "owner" ? { store_name: storeName.trim() } : { invite_code: inviteCode.trim().toUpperCase() })
            },
            emailRedirectTo: `${window.location.origin}/Pos/`
          }
        });
        if (error) throw error;
        if (!data.session) {
          setVerificationEmail(email.trim());
          setVerificationPending(true);
          setResendCooldown(45);
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

  if (verificationPending) return <main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">
    <section className="w-full max-w-md rounded-3xl border border-slate-100 bg-white p-8 text-center shadow-soft">
      <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-700"><MailIcon/></div>
      <h1 className="text-2xl font-extrabold">ตรวจสอบอีเมลของคุณ</h1>
      <p className="mt-3 text-sm leading-6 text-slate-600">สมัครสมาชิก StoreFlow สำเร็จแล้ว เราส่งลิงก์ยืนยันไปที่</p>
      <p className="mt-2 break-all font-semibold text-slate-900">{verificationEmail}</p>
      <p className="mt-4 rounded-xl bg-emerald-50 p-4 text-left text-sm leading-6 text-emerald-900">กรุณาเปิดอีเมลจาก Supabase แล้วกดปุ่มยืนยันอีเมลก่อนเข้าสู่ระบบ หากไม่พบ ให้ตรวจสอบโฟลเดอร์ Spam หรือ Promotions ด้วย</p>
      {notice && <p role="status" className="mt-4 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
      {error && <p role="alert" className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
      <button type="button" disabled={resendBusy || resendCooldown > 0} onClick={resendConfirmation} className="mt-5 w-full rounded-xl bg-emerald-600 py-3 font-semibold text-white disabled:opacity-50">{resendBusy ? "กำลังส่ง..." : resendCooldown > 0 ? `ส่งอีเมลอีกครั้งได้ใน ${resendCooldown} วินาที` : "ส่งอีเมลยืนยันอีกครั้ง"}</button>
      <button type="button" onClick={()=>{setVerificationPending(false);setMode("login");setNotice("");setError("");}} className="mt-3 w-full rounded-xl border border-slate-200 py-3 text-sm font-semibold text-slate-600">กลับไปหน้าเข้าสู่ระบบ</button>
    </section>
  </main>;

  return <main className="flex min-h-screen items-center justify-center bg-slate-50 p-4">
    <form onSubmit={submit} className="w-full max-w-md rounded-3xl border border-slate-100 bg-white p-8 shadow-soft">
      <div className="mb-7 flex items-center gap-3"><div className="rounded-xl bg-emerald-600 p-3 text-white">SF</div><div><h1 className="text-2xl font-extrabold">Store<span className="text-emerald-600">Flow</span></h1><p className="text-xs text-slate-400">STORE MANAGEMENT SUITE</p></div></div>
      <h2 className="text-xl font-bold">{mode === "login" ? "เข้าสู่ระบบ" : "สร้างบัญชี StoreFlow"}</h2>
      <p className="mb-6 mt-1 text-sm text-slate-500">{mode === "login" ? "ลงชื่อเข้าใช้บัญชีร้านค้าของคุณ" : "เลือกประเภทบัญชีที่ต้องการสมัคร"}</p>
      {mode === "signup" && <>
        <div className="mb-4 grid grid-cols-2 gap-2">
          <button type="button" onClick={()=>setSignupRole("owner")} className={signupRole==="owner"?"rounded-xl border-2 border-emerald-500 bg-emerald-50 p-3 text-sm font-semibold text-emerald-800":"rounded-xl border border-slate-200 p-3 text-sm text-slate-600"}>เจ้าของร้าน</button>
          <button type="button" onClick={()=>setSignupRole("cashier")} className={signupRole==="cashier"?"rounded-xl border-2 border-emerald-500 bg-emerald-50 p-3 text-sm font-semibold text-emerald-800":"rounded-xl border border-slate-200 p-3 text-sm text-slate-600"}>พนักงาน / แคชเชียร์</button>
        </div>
        <label className="mb-4 block text-sm font-medium">ชื่อที่แสดง<input required value={name} onChange={e=>setName(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="ชื่อของคุณ"/></label>
        {signupRole === "owner"
          ? <><label className="mb-4 block text-sm font-medium">ชื่อร้านค้า<input required minLength={2} maxLength={120} value={storeName} onChange={e=>setStoreName(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="เช่น ร้านสมใจ มินิมาร์ท"/></label><p className="mb-4 rounded-xl bg-emerald-50 p-3 text-xs text-emerald-800">รับสิทธิ์ทดลองใช้ฟรี 7 วัน พร้อมสร้างรหัสเชิญพนักงานอัตโนมัติ</p></>
          : <label className="mb-4 block text-sm font-medium">รหัสเชิญร้าน<input required value={inviteCode} onChange={e=>setInviteCode(e.target.value.toUpperCase())} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 uppercase tracking-widest outline-none focus:border-emerald-500" placeholder="กรอกรหัสจากเจ้าของร้าน"/><p className="mt-1 text-xs text-slate-400">ระบบจะส่งคำขอเข้าร่วมและรอเจ้าของร้านอนุมัติ</p></label>}
      </>}
      <label className="mb-4 block text-sm font-medium">อีเมล<input required type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="you@example.com"/></label>
      <label className="mb-4 block text-sm font-medium">รหัสผ่าน<input required minLength={8} type="password" autoComplete={mode === "login" ? "current-password" : "new-password"} value={password} onChange={e=>setPassword(e.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 px-3 py-3 outline-none focus:border-emerald-500" placeholder="อย่างน้อย 8 ตัวอักษร"/></label>
      {error && <p role="alert" className="mb-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
      {notice && <p role="status" className="mb-4 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
      <button disabled={busy} className="w-full rounded-xl bg-emerald-600 py-3 font-semibold text-white disabled:opacity-60">{busy ? "กำลังดำเนินการ..." : mode === "login" ? "เข้าสู่ระบบ" : "สมัครสมาชิก"}</button>
      <button type="button" onClick={()=>{setMode(mode === "login" ? "signup" : "login");setError("");setNotice("");}} className="mt-4 w-full rounded-xl border border-slate-200 py-3 text-sm font-semibold text-slate-600">{mode === "login" ? "ยังไม่มีบัญชี? สมัครสมาชิก" : "มีบัญชีอยู่แล้ว? เข้าสู่ระบบ"}</button>
      <p className="mt-5 text-center text-xs leading-5 text-slate-400">บัญชีและรหัสผ่านจัดการผ่าน Supabase Auth<br/>สิทธิ์ร้านค้าจะถูกกำหนดจากข้อมูลสมาชิกในฐานข้อมูล</p>
    </form>
  </main>;
}

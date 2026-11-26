"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function AccountDeletionPage() {
  const supabase = useMemo(() => createClient(), []);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [sessionEmail, setSessionEmail] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSessionEmail(data.session?.user.email ?? null));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setSessionEmail(session?.user.email ?? null);
    });
    return () => data.subscription.unsubscribe();
  }, [supabase]);

  async function signIn() {
    setBusy(true); setMessage("");
    try {
      const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
      setMessage("ยืนยันตัวตนแล้ว กรุณาอ่านคำเตือนและยืนยันการลบข้อมูลด้านล่าง");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "เข้าสู่ระบบไม่สำเร็จ");
    } finally { setBusy(false); }
  }

  async function sendMagicLink() {
    setBusy(true); setMessage("");
    try {
      const redirectTo = window.location.href;
      const { error } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        options: { emailRedirectTo: redirectTo, shouldCreateUser: false },
      });
      if (error) throw error;
      setMessage("ส่งลิงก์ยืนยันตัวตนไปยังอีเมลแล้ว กรุณาเปิดลิงก์จากอุปกรณ์นี้");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "ส่งลิงก์ไม่สำเร็จ");
    } finally { setBusy(false); }
  }

  async function requestDeletion() {
    if (!confirm) return;
    setBusy(true); setMessage("");
    try {
      const { error } = await supabase.functions.invoke("storeflow-delete-account", {
        body: { confirm: "DELETE MY ACCOUNT" },
      });
      if (error) throw error;
      await supabase.auth.signOut();
      setSessionEmail(null);
      setMessage("ดำเนินการลบบัญชีและข้อมูลที่เกี่ยวข้องเรียบร้อยแล้ว");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "ดำเนินการลบบัญชีไม่สำเร็จ");
    } finally { setBusy(false); }
  }

  return (
    <main className="min-h-screen bg-slate-50 px-4 py-10 text-slate-800">
      <section className="mx-auto max-w-xl rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        <p className="text-sm font-semibold text-emerald-700">StoreFlow</p>
        <h1 className="mt-2 text-2xl font-bold">ขอลบบัญชีและข้อมูลส่วนบุคคล</h1>
        <p className="mt-3 text-sm leading-6 text-slate-600">
          หน้านี้ใช้สำหรับเจ้าของบัญชี StoreFlow ที่ต้องการลบบัญชีโดยไม่ต้องติดตั้งแอป
          กรุณายืนยันตัวตนด้วยอีเมลที่ใช้กับ StoreFlow ก่อนส่งคำขอ
        </p>

        {!sessionEmail ? (
          <div className="mt-6 space-y-3">
            <label className="block text-sm font-medium">อีเมลบัญชี StoreFlow</label>
            <input className="w-full rounded-lg border border-slate-300 px-3 py-3" type="email"
              autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            <label className="block text-sm font-medium">รหัสผ่าน (หากตั้งไว้)</label>
            <input className="w-full rounded-lg border border-slate-300 px-3 py-3" type="password"
              autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} />
            <button disabled={busy || !email.includes("@") || !password}
              onClick={signIn} className="w-full rounded-lg bg-emerald-700 px-4 py-3 font-semibold text-white disabled:opacity-50">
              {busy ? "กำลังตรวจสอบ..." : "เข้าสู่ระบบเพื่อยืนยันตัวตน"}
            </button>
            <button disabled={busy || !email.includes("@")} onClick={sendMagicLink}
              className="w-full rounded-lg border border-slate-300 px-4 py-3 font-semibold disabled:opacity-50">
              ส่งลิงก์ยืนยันทางอีเมล
            </button>
          </div>
        ) : (
          <div className="mt-6 space-y-4">
            <div className="rounded-lg bg-emerald-50 p-3 text-sm">
              ยืนยันตัวตนแล้ว: <strong>{sessionEmail}</strong>
            </div>
            <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm leading-6 text-red-900">
              <strong>คำเตือน: การลบไม่สามารถย้อนกลับได้</strong>
              <ul className="mt-2 list-disc pl-5">
                <li>ร้านที่คุณเป็นเจ้าของคนเดียวจะถูกลบพร้อมข้อมูลและไฟล์ของร้าน ส่วนร้านที่มีเจ้าของร่วมจะยังคงใช้งานได้</li>
                <li>หากร้านมีสมาชิกอื่นแต่ไม่มีเจ้าของร่วม ระบบจะให้โอนสิทธิ์เจ้าของก่อน เพื่อป้องกันร้านและข้อมูลสูญหาย</li>
                <li>การเป็นสมาชิกในร้านอื่นจะถูกยกเลิก และประวัติธุรกรรมที่จำเป็นจะถูกเก็บโดยไม่ระบุบัญชีผู้ใช้</li>
                <li>หากมีการเรียกเก็บเงินผ่าน Stripe ที่ยังทำงานอยู่ ต้องยกเลิกก่อนดำเนินการลบ</li>
                <li>แนะนำให้ส่งออกไฟล์สำรอง JSON จากแอปก่อนลบบัญชี</li>
              </ul>
            </div>
            <label className="flex items-start gap-3 text-sm">
              <input type="checkbox" checked={confirm} onChange={(e) => setConfirm(e.target.checked)} className="mt-1" />
              ฉันเข้าใจและยืนยันว่าต้องการลบบัญชี StoreFlow และข้อมูลร้านที่ฉันเป็นเจ้าของ
            </label>
            <button disabled={busy || !confirm} onClick={requestDeletion}
              className="w-full rounded-lg bg-red-700 px-4 py-3 font-semibold text-white disabled:opacity-50">
              {busy ? "กำลังดำเนินการ..." : "ลบบัญชีและข้อมูลถาวร"}
            </button>
            <button disabled={busy} onClick={() => supabase.auth.signOut()}
              className="w-full rounded-lg border border-slate-300 px-4 py-3 font-semibold">
              ออกจากระบบ
            </button>
          </div>
        )}
        {message && <p role="status" className="mt-4 rounded-lg bg-slate-100 p-3 text-sm">{message}</p>}
        <p className="mt-6 text-xs leading-5 text-slate-500">
          หากไม่สามารถยืนยันตัวตนได้ โปรดติดต่อผู้ดูแล StoreFlow ผ่านช่องทางสนับสนุนที่ระบุในนโยบายความเป็นส่วนตัว
        </p>
      </section>
    </main>
  );
}

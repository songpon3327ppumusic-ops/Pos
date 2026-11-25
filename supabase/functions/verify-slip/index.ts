import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://songpon3327ppumusic-ops.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const encoder = new TextEncoder();
const decoder = new TextDecoder();

async function getCryptoKey(secret: string) {
  if (secret.length !== 32) throw new Error("SLIP_CREDENTIALS_ENCRYPTION_KEY must be exactly 32 characters");
  return crypto.subtle.importKey("raw", encoder.encode(secret), "AES-GCM", false, ["encrypt", "decrypt"]);
}
async function encryptSecret(value: string, secret: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await getCryptoKey(secret);
  const cipher = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, encoder.encode(value));
  return { encrypted: btoa(String.fromCharCode(...new Uint8Array(cipher))), nonce: btoa(String.fromCharCode(...iv)) };
}
async function decryptSecret(value: string, nonce: string, secret: string) {
  const key = await getCryptoKey(secret);
  const cipher = Uint8Array.from(atob(value), c => c.charCodeAt(0));
  const iv = Uint8Array.from(atob(nonce), c => c.charCodeAt(0));
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, cipher);
  return decoder.decode(plain);
}
const digits = (value: unknown) => String(value ?? "").replace(/\D/g, "");
const suffix = (value: unknown) => digits(value).slice(-4);
const normalizeName = (value: unknown) => String(value ?? "").normalize("NFKC").replace(/\s+/g, "").toLocaleLowerCase("th-TH");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Authentication required" }, 401);
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const masterKey = Deno.env.get("SLIP_CREDENTIALS_ENCRYPTION_KEY");
    if (!url || !anon || !service) return json({ error: "Supabase function is not configured" }, 503);
    const userClient = createClient(url, anon);
    const { data: { user }, error: authError } = await userClient.auth.getUser(token);
    if (authError || !user) return json({ error: "Invalid session" }, 401);
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json();
    const action = String(body.action ?? "verify");
    const organizationId = String(body.organization_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(organizationId)) return json({ error: "Invalid organization" }, 400);
    const { data: member, error: memberError } = await admin.from("organization_members")
      .select("role,is_active,membership_status").eq("organization_id", organizationId).eq("user_id", user.id).maybeSingle();
    if (memberError) throw memberError;
    if (!member?.is_active || member.membership_status !== "active") return json({ error: "Active store membership required" }, 403);

    if (action === "status") {
      if (member.role !== "owner") return json({ error: "Only the store owner can view provider configuration" }, 403);
      const { data, error } = await admin.from("store_slip_provider_credentials").select("provider,configured_at").eq("organization_id", organizationId).maybeSingle();
      if (error) throw error;
      return json({ configured: Boolean(data), provider: data?.provider ?? null, configured_at: data?.configured_at ?? null });
    }

    if (action === "configure") {
      if (member.role !== "owner") return json({ error: "Only the store owner can configure the slip provider" }, 403);
      if (!masterKey) return json({ error: "กรุณาตั้ง Supabase Function Secret SLIP_CREDENTIALS_ENCRYPTION_KEY (32 ตัวอักษร) ก่อนบันทึก API Key" }, 503);
      const apiKey = String(body.api_key ?? "").trim();
      if (apiKey.length < 12 || apiKey.length > 512) return json({ error: "รูปแบบ API Key ไม่ถูกต้อง" }, 400);
      const encrypted = await encryptSecret(apiKey, masterKey);
      const { error } = await admin.from("store_slip_provider_credentials").upsert({
        organization_id: organizationId, provider: "easyslip",
        encrypted_api_key: encrypted.encrypted, nonce: encrypted.nonce,
        configured_by: user.id, configured_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      }, { onConflict: "organization_id" });
      if (error) throw error;
      return json({ configured: true, provider: "easyslip", message: "EasySlip API Key ถูกเข้ารหัสและบันทึกแล้ว" });
    }

    if (action !== "verify") return json({ error: "Unsupported action" }, 400);
    if (!["owner", "admin", "manager", "cashier"].includes(member.role)) return json({ error: "ไม่มีสิทธิ์ตรวจสอบสลิป" }, 403);
    if (!masterKey) return json({ error: "Slip verification encryption key is not configured" }, 503);
    const saleId = String(body.sale_id ?? "");
    const slipPath = String(body.slip_path ?? "");
    const clientRef = String(body.transaction_ref ?? "").trim();
    const qrPayload = String(body.qr_payload ?? "").trim();
    if (!/^[0-9a-f-]{36}$/i.test(saleId) || !slipPath.startsWith(organizationId + "/slips/" + saleId + "/") || !qrPayload || qrPayload.length > 2048) {
      return json({ error: "ต้องมีบิล รูปสลิป และ QR transaction reference ที่ถูกต้อง" }, 400);
    }
    const { data: sale, error: saleError } = await admin.from("sales").select("id,receipt_no,total,payment_method,payment_status,verification_status")
      .eq("id", saleId).eq("organization_id", organizationId).single();
    if (saleError) throw saleError;
    if (sale.payment_status !== "pending" || !["QR PromptPay", "โอนเงิน", "bank_transfer", "transfer"].includes(sale.payment_method)) {
      return json({ error: "บิลนี้ไม่ได้อยู่ในสถานะรอตรวจสอบการโอน" }, 409);
    }
    const { data: settings, error: settingsError } = await admin.from("store_payment_settings")
      .select("bank_account_number,bank_account_name,promptpay_id,promptpay_name").eq("organization_id", organizationId).maybeSingle();
    if (settingsError) throw settingsError;

    if (clientRef) {
      const { data: existing } = await admin.from("payment_slips").select("sale_id")
        .eq("organization_id", organizationId).eq("transaction_ref", clientRef).maybeSingle();
      if (existing && existing.sale_id !== saleId) {
        const { data: prior } = await admin.from("sales").select("receipt_no").eq("id", existing.sale_id).maybeSingle();
        return json({ verified: false, duplicate: true, message: "สลิปนี้ถูกใช้งานไปแล้วในบิลเลขที่ " + (prior?.receipt_no ?? existing.sale_id) }, 409);
      }
      const { data: priorSale } = await admin.from("sales").select("receipt_no")
        .eq("organization_id", organizationId).eq("transaction_ref", clientRef).neq("id", saleId).maybeSingle();
      if (priorSale) return json({ verified: false, duplicate: true, message: "สลิปนี้ถูกใช้งานไปแล้วในบิลเลขที่ " + priorSale.receipt_no }, 409);
    }

    const { data: storedSlip, error: downloadError } = await admin.storage.from("store-payment-assets").download(slipPath);
    if (downloadError || !storedSlip) throw new Error("ไม่พบไฟล์สลิปในพื้นที่จัดเก็บของร้าน");
    if (storedSlip.size > 4 * 1024 * 1024) return json({ error: "ไฟล์สลิปต้องไม่เกิน 4 MB" }, 413);
    const mime = storedSlip.type.toLowerCase();
    if (!["image/jpeg", "image/png", "image/webp"].includes(mime)) return json({ error: "ชนิดไฟล์สลิปไม่รองรับ" }, 415);

    const { data: credential, error: credentialError } = await admin.from("store_slip_provider_credentials")
      .select("provider,encrypted_api_key,nonce").eq("organization_id", organizationId).maybeSingle();
    if (credentialError) throw credentialError;
    if (!credential) {
      const { error } = await admin.from("sales").update({
        slip_url: slipPath, slip_path: slipPath, transaction_ref: clientRef || null,
        verification_status: "pending_review", verification_provider: null,
        verification_response: { reason: "provider_not_configured" },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      if (error) throw error;
      return json({ verified: false, pending_review: true, message: "ยังไม่ได้ตั้งค่า EasySlip — ส่งบิลให้เจ้าของร้านตรวจสอบด้วยตนเอง" }, 202);
    }
    const apiKey = await decryptSecret(credential.encrypted_api_key, credential.nonce, masterKey);
    const form = new FormData();
    form.append("image", storedSlip, "storeflow-slip." + (mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg"));
    form.append("matchAccount", "true");
    form.append("matchAmount", String(Number(sale.total)));
    form.append("checkDuplicate", "true");
    form.append("remark", "StoreFlow " + sale.receipt_no);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    let providerResponse: Response;
    try {
      providerResponse = await fetch("https://api.easyslip.com/v2/verify/bank", {
        method: "POST", headers: { Authorization: "Bearer " + apiKey }, body: form, signal: controller.signal,
      });
    } finally { clearTimeout(timeout); }
    const providerBody = await providerResponse.json().catch(() => ({}));
    if (!providerResponse.ok || providerBody.success !== true) {
      const code = String(providerBody.error?.code ?? "");
      const retryable = providerResponse.status >= 500 || providerResponse.status === 429 || providerResponse.status === 401 || providerResponse.status === 403 || code === "QUOTA_EXCEEDED" || code === "SLIP_PENDING";
      if (retryable) {
        const { error } = await admin.from("sales").update({
          slip_url: slipPath, slip_path: slipPath, transaction_ref: clientRef || null,
          verification_status: "pending_review", verification_provider: "easyslip",
          verification_response: { provider_status: providerResponse.status, provider_code: code, reason: "provider_unavailable" },
        }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
        if (error && error.code !== "23505") throw error;
        return json({ verified: false, pending_review: true, message: "ผู้ให้บริการตรวจสลิปไม่พร้อมใช้งาน บิลถูกส่งให้เจ้าของร้านตรวจสอบ" }, 202);
      }
      await admin.from("sales").update({
        slip_url: slipPath, slip_path: slipPath, verification_status: "rejected",
        verification_provider: "easyslip",
        verification_response: { provider_status: providerResponse.status, provider_code: code, reason: "provider_rejected" },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, rejected: true, message: providerBody.error?.message ?? "ผู้ให้บริการไม่พบธุรกรรมที่ถูกต้อง" }, 422);
    }

    const result = providerBody.data ?? {};
    const raw = result.rawSlip ?? {};
    const serverRef = String(raw.transRef ?? "").trim();
    if (result.isDuplicate === true) {
      const { data: prior } = serverRef ? await admin.from("sales").select("receipt_no").eq("organization_id", organizationId).eq("transaction_ref", serverRef).neq("id", saleId).maybeSingle() : { data: null };
      await admin.from("sales").update({ slip_url: slipPath, slip_path: slipPath, verification_status: "rejected", verification_provider: "easyslip", verification_response: { reason: "duplicate_slip", transaction_ref: serverRef } }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, duplicate: true, message: "สลิปนี้ถูกใช้งานไปแล้ว" + (prior?.receipt_no ? "ในบิลเลขที่ " + prior.receipt_no : "") }, 409);
    }
    if (!serverRef || (clientRef && serverRef !== clientRef) || String(raw.payload ?? "") !== qrPayload) {
      return json({ verified: false, rejected: true, message: "ข้อมูล QR จากรูปภาพไม่ตรงกับข้อมูลที่ตรวจสอบจากผู้ให้บริการ" }, 422);
    }
    const amount = Number(raw.amount?.amount ?? result.amountInSlip ?? 0);
    const amountMatched = result.isAmountMatched === true && Math.round(amount * 100) === Math.round(Number(sale.total) * 100);
    if (!amountMatched || String(raw.amount?.local?.currency ?? "THB").toUpperCase() !== "THB") {
      await admin.from("sales").update({ slip_url: slipPath, slip_path: slipPath, transaction_ref: serverRef,
        verification_status: "rejected", verification_provider: "easyslip",
        verification_response: { reason: "amount_mismatch", amount, expected: Number(sale.total) },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, rejected: true, message: "ยอดเงินหรือสกุลเงินในสลิปไม่ตรงกับยอดสุทธิของบิล" }, 422);
    }
    if (result.matchedAccount == null) {
      await admin.from("sales").update({ slip_url: slipPath, slip_path: slipPath, transaction_ref: serverRef,
        verification_status: "rejected", verification_provider: "easyslip",
        verification_response: { reason: "recipient_not_matched" },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, rejected: true, message: "บัญชีผู้รับเงินไม่ตรงกับบัญชีร้านที่ลงทะเบียนไว้ใน EasySlip" }, 422);
    }
    const expectedBank = digits(settings?.bank_account_number);
    const expectedPromptPay = digits(settings?.promptpay_id);
    const expectedName = normalizeName(settings?.bank_account_name || settings?.promptpay_name);
    const matchedAccount = result.matchedAccount ?? {};
    const receiverAccount = raw.receiver?.account ?? {};
    const receiverBank = matchedAccount.bankNumber || receiverAccount.bank?.account || "";
    const receiverProxy = receiverAccount.proxy?.account || "";
    let recipientCheckAvailable = false;
    let recipientMatched = false;
    if (expectedBank.length >= 4) {
      recipientCheckAvailable = digits(receiverBank).length >= 4;
      recipientMatched = recipientCheckAvailable && suffix(receiverBank) === suffix(expectedBank);
    } else if (expectedPromptPay.length >= 4 && digits(receiverProxy).length >= expectedPromptPay.length) {
      recipientCheckAvailable = true;
      recipientMatched = suffix(receiverProxy) === suffix(expectedPromptPay);
    } else if (expectedName && normalizeName(matchedAccount.nameTh)) {
      recipientCheckAvailable = true;
      recipientMatched = expectedName === normalizeName(matchedAccount.nameTh);
    }
    if (!recipientCheckAvailable) {
      await admin.from("sales").update({ slip_url: slipPath, slip_path: slipPath, transaction_ref: serverRef,
        verification_status: "pending_review", verification_provider: "easyslip",
        verification_response: { reason: "store_recipient_details_insufficient" },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, pending_review: true, message: "ข้อมูลบัญชีรับเงินของร้านยังไม่เพียงพอสำหรับยืนยันอัตโนมัติ กรุณาตั้งเลขบัญชีและชื่อบัญชี" }, 202);
    }
    if (!recipientMatched) {
      await admin.from("sales").update({ slip_url: slipPath, slip_path: slipPath, transaction_ref: serverRef,
        verification_status: "rejected", verification_provider: "easyslip",
        verification_response: { reason: "recipient_account_mismatch" },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, rejected: true, message: "บัญชีผู้รับเงินในสลิปไม่ตรงกับบัญชีรับเงินของร้าน" }, 422);
    }
    const transferAt = new Date(String(raw.date ?? ""));
    const ageMs = Date.now() - transferAt.getTime();
    if (!Number.isFinite(transferAt.getTime()) || ageMs < -120000 || ageMs > 30 * 60 * 1000) {
      await admin.from("sales").update({ slip_url: slipPath, slip_path: slipPath, transaction_ref: serverRef,
        verification_status: "rejected", verification_provider: "easyslip",
        verification_response: { reason: "transfer_not_recent", transfer_at: Number.isFinite(transferAt.getTime()) ? transferAt.toISOString() : null },
      }).eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending");
      return json({ verified: false, rejected: true, message: "สลิปต้องเป็นธุรกรรมที่เกิดขึ้นภายใน 30 นาทีล่าสุด" }, 422);
    }

    const safeResponse = {
      provider: "easyslip", isDuplicate: false, isAmountMatched: true,
      amountInSlip: amount, matchedAccount: {
        bank: matchedAccount.bank ?? null, nameTh: matchedAccount.nameTh ?? null,
        bankNumber: matchedAccount.bankNumber ?? null,
      },
      transferAt: transferAt.toISOString(), transRef: serverRef,
    };
    const { error: finalizeError } = await admin.rpc("finalize_verified_pos_slip", {
      p_organization_id: organizationId, p_sale_id: saleId, p_slip_url: slipPath,
      p_transaction_ref: serverRef, p_provider: "easyslip", p_amount: amount, p_currency: "THB",
      p_transfer_at: transferAt.toISOString(), p_receiver: safeResponse.matchedAccount,
      p_verification_response: safeResponse, p_uploaded_by: user.id,
    });
    if (finalizeError) {
      if (finalizeError.code === "23505") return json({ verified: false, duplicate: true, message: "สลิปนี้ถูกใช้งานไปแล้วในบิลอื่น" }, 409);
      throw finalizeError;
    }
    return json({ verified: true, verification_status: "verified", transaction_ref: serverRef, message: "ตรวจสอบสลิปและยืนยันยอดเงินจริงสำเร็จ" });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Slip verification failed" }, 500);
  }
});
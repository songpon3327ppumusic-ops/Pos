import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigin = "https://songpon3327ppumusic-ops.github.io";
const headers = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
  "Cache-Control": "no-store",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...headers, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (origin && origin !== allowedOrigin) return json({ error: "Origin not allowed" }, 403);
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anon || !serviceKey) return json({ error: "Account deletion is not configured" }, 503);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "กรุณาเข้าสู่ระบบก่อน" }, 401);

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "เซสชันไม่ถูกต้อง กรุณาเข้าสู่ระบบใหม่" }, 401);

    const declaredLength = Number(req.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > 4096) return json({ error: "Request payload too large" }, 413);
    const raw = await req.text();
    if (new TextEncoder().encode(raw).byteLength > 4096) return json({ error: "Request payload too large" }, 413);
    const body = JSON.parse(raw || "{}");
    if (body?.confirm !== "DELETE MY ACCOUNT") {
      return json({ error: "ต้องยืนยันข้อความ DELETE MY ACCOUNT" }, 400);
    }

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: cleanup, error: cleanupError } = await admin.rpc(
      "storeflow_prepare_account_deletion",
      { p_user_id: userData.user.id },
    );
    if (cleanupError) {
      if (cleanupError.code === "55000") return json({ error: cleanupError.message }, 409);
      throw cleanupError;
    }

    // Only remove objects for stores actually deleted by database cleanup.
    // Co-owned stores are retained and their assets must remain intact.
    const deletedOrgIds: string[] = Array.isArray(cleanup?.deleted_org_ids)
      ? cleanup.deleted_org_ids.filter((id: unknown): id is string => typeof id === "string")
      : [];
    const buckets = [
      "business-documents", "store-assets", "store-payment-assets",
      "storeflow-pos-slips", "storeflow-store-assets",
    ];
    for (const bucketName of buckets) {
      const bucket = admin.storage.from(bucketName);
      async function removeTree(prefix: string): Promise<void> {
        const files: string[] = [];
        let offset = 0;
        while (true) {
          const { data, error } = await bucket.list(prefix, { limit: 1000, offset });
          if (error) throw error;
          const page = data ?? [];
          for (const item of page) {
            const path = prefix ? prefix + "/" + item.name : item.name;
            if (item.id === null) await removeTree(path);
            else files.push(path);
          }
          if (page.length < 1000) break;
          offset += page.length;
        }
        for (let index = 0; index < files.length; index += 1000) {
          const { error: removeError } = await bucket.remove(files.slice(index, index + 1000));
          if (removeError) throw removeError;
        }
      }
      for (const organizationId of deletedOrgIds) await removeTree(organizationId);
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(userData.user.id);
    if (deleteError) throw deleteError;

    return json({
      success: true,
      message: "ลบบัญชีและข้อมูลที่เกี่ยวข้องเรียบร้อยแล้ว",
      cleanup,
    });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "เกิดข้อผิดพลาดในการลบบัญชี",
    }, 500);
  }
});

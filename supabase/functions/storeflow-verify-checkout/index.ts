import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://songpon3327ppumusic-ops.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Authentication required" }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) return json({ error: "Billing is not configured" }, 503);

    const userClient = createClient(url, anon);
    const { data: { user }, error: authError } = await userClient.auth.getUser(token);
    if (authError || !user) return json({ error: "Invalid session" }, 401);

    const { organization_id, session_id } = await req.json();
    if (typeof organization_id !== "string" || typeof session_id !== "string" || !/^cs_(test|live)_[A-Za-z0-9]+$/.test(session_id)) {
      return json({ error: "Invalid checkout reference" }, 400);
    }

    const admin = createClient(url, service);
    const { data: member } = await admin.from("organization_members")
      .select("role,is_active,membership_status")
      .eq("organization_id", organization_id).eq("user_id", user.id).maybeSingle();
    if (!member?.is_active || member.membership_status !== "active" || !["owner", "admin"].includes(member.role)) {
      return json({ error: "Only an active store owner or admin can verify billing" }, 403);
    }

    const stripeResponse = await fetch(`https://api.stripe.com/v1/checkout/sessions/${encodeURIComponent(session_id)}`, {
      headers: { Authorization: `Bearer ${stripeKey}` },
    });
    const session = await stripeResponse.json();
    if (!stripeResponse.ok) return json({ error: "Stripe could not verify this checkout session" }, 502);
    const configuredLiveMode = stripeKey.startsWith("sk_live_");
    if (Boolean(session.livemode) !== configuredLiveMode) return json({ verified: false, status: "mode_mismatch" }, 403);

    if (session.client_reference_id !== organization_id || session.metadata?.organization_id !== organization_id) {
      return json({ verified: false, status: "mismatch" }, 403);
    }
    if (session.mode === "payment" && session.payment_status !== "paid") {
      return json({ verified: false, status: session.payment_status || "unpaid" });
    }
    if (session.mode === "subscription" && !session.subscription) {
      return json({ verified: false, status: "subscription_pending" });
    }

    // Webhook is the only writer of entitlements. This endpoint only confirms
    // that the verified Stripe session has already been applied to this store.
    const { data: current, error: subError } = await admin.from("organization_subscriptions")
      .select("plan_id,status,plan_type,stripe_subscription_id,metadata,current_period_end,trial_ends_at")
      .eq("organization_id", organization_id).maybeSingle();
    if (subError) throw subError;

    const webhookSessionId = current?.metadata?.checkout_session_id;
    const isLifetime = session.mode === "payment" && session.payment_status === "paid"
      && current?.plan_type === "lifetime" && current?.status === "active"
      && current?.plan_id === session.metadata?.plan_id && webhookSessionId === session.id;
    const isRecurring = session.mode === "subscription"
      && ["active", "trialing"].includes(current?.status)
      && current?.stripe_subscription_id === session.subscription
      && current?.plan_id === session.metadata?.plan_id
      && webhookSessionId === session.id;

    if (!isLifetime && !isRecurring) {
      return json({ verified: false, status: "webhook_pending", message: "Stripe confirms payment, waiting for webhook entitlement update." }, 202);
    }
    return json({
      verified: true,
      mode: session.mode,
      plan_id: current.plan_id,
      status: current.status,
      current_period_end: current.current_period_end,
      trial_ends_at: current.trial_ends_at,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

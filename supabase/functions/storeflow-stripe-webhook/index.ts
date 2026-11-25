import { createClient } from "npm:@supabase/supabase-js@2";

const encoder = new TextEncoder();
const toHex = (bytes: Uint8Array) => [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");

async function verifyStripeSignature(rawBody: string, header: string, secret: string) {
  const parts = header.split(",").map((part) => part.trim().split("="));
  const timestamp = parts.find(([key]) => key === "t")?.[1];
  const signatures = parts.filter(([key]) => key === "v1").map(([, value]) => value);
  if (!timestamp || !signatures.length || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;

  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const expected = toHex(new Uint8Array(await crypto.subtle.sign(
    "HMAC", key, encoder.encode(`${timestamp}.${rawBody}`),
  )));
  // Compare every v1 signature without early exit.
  let valid = false;
  for (const candidate of signatures) {
    if (!/^[a-f0-9]{64}$/i.test(candidate)) continue;
    let diff = expected.length ^ candidate.length;
    for (let i = 0; i < expected.length; i++) {
      diff |= expected.charCodeAt(i) ^ (candidate.charCodeAt(i) || 0);
    }
    if (diff === 0) valid = true;
  }
  return valid;
}

async function stripeGet(path: string, secret: string) {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error?.message ?? "Stripe API request failed");
  return body;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  try {
    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!webhookSecret || !stripeSecret || !supabaseUrl || !serviceRole) {
      return new Response("Webhook is not configured", { status: 503 });
    }

    const declaredLength = Number(req.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > 2_000_000) {
      return new Response("Webhook payload too large", { status: 413 });
    }
    const rawBody = await req.text();
    if (new TextEncoder().encode(rawBody).byteLength > 2_000_000) {
      return new Response("Webhook payload too large", { status: 413 });
    }
    const signature = req.headers.get("Stripe-Signature") ?? "";
    if (!(await verifyStripeSignature(rawBody, signature, webhookSecret))) {
      return new Response("Invalid Stripe signature", { status: 400 });
    }

    const event = JSON.parse(rawBody);
    if (Boolean(event.livemode) !== stripeSecret.startsWith("sk_live_")) {
      return new Response("Stripe test/live mode mismatch", { status: 400 });
    }
    const object = event.data?.object ?? {};
    const admin = createClient(supabaseUrl, serviceRole);

    // Store POS direct charges arrive as Connect events on the same signed webhook endpoint.
    if (event.account && ["checkout.session.completed", "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed", "checkout.session.expired"].includes(event.type) && object.metadata?.sale_id && object.metadata?.organization_id) {
      const organizationId = String(object.metadata.organization_id);
      const saleId = String(object.metadata.sale_id);
      const { data: paymentSettings, error: settingsError } = await admin.from("store_payment_settings")
        .select("stripe_connect_account_id").eq("organization_id", organizationId).maybeSingle();
      if (settingsError) throw settingsError;
      if (!paymentSettings || paymentSettings.stripe_connect_account_id !== event.account) {
        throw new Error("Stripe connected account does not match this store");
      }
      const { data: previousEvent, error: previousError } = await admin.from("pos_payment_events")
        .select("id").eq("stripe_event_id", event.id).maybeSingle();
      if (previousError) throw previousError;
      if (previousEvent) return Response.json({ received: true, duplicate: true, payment: "pos" });
      const { data: sale, error: saleError } = await admin.from("sales")
        .select("id,total,payment_status,payment_method,stripe_checkout_session_id").eq("id", saleId).eq("organization_id", organizationId).single();
      if (saleError) throw saleError;
      if (sale.payment_method !== "Stripe Online") throw new Error("Sale is not a Stripe POS payment");
      // Ignore stale sessions after a newer checkout attempt has been claimed.
      if (sale.stripe_checkout_session_id !== object.id) {
        const { error: staleEventError } = await admin.from("pos_payment_events").insert({
          stripe_event_id: event.id, organization_id: organizationId, sale_id: saleId, event_type: event.type,
        });
        if (staleEventError && staleEventError.code !== "23505") throw staleEventError;
        return Response.json({ received: true, stale_session: true });
      }
      if (event.type === "checkout.session.expired" || event.type === "checkout.session.async_payment_failed") {
        if (sale.payment_status === "pending") {
          const { error } = await admin.from("sales").update({ payment_status: "failed", status: "payment_failed", stripe_checkout_session_id: null, payment_attempt_started_at: null })
            .eq("id", saleId).eq("organization_id", organizationId).eq("payment_status", "pending").eq("stripe_checkout_session_id", object.id);
          if (error) throw error;
        }
      } else {
        if (object.payment_status !== "paid") {
          return Response.json({ received: true, payment: "awaiting_settlement" });
        }
        if (object.mode !== "payment" || object.currency !== "thb" || Number(object.amount_total) !== Math.round(Number(sale.total) * 100)) {
          throw new Error("Stripe amount or currency does not match the POS sale");
        }
        const { error } = await admin.from("sales").update({
          payment_status: "paid", status: "completed", paid_at: new Date().toISOString(),
          amount_tendered: Number(sale.total), payment_ref: object.payment_intent ?? object.id, payment_attempt_started_at: null,
        }).eq("id", saleId).eq("organization_id", organizationId).eq("stripe_checkout_session_id", object.id).in("payment_status", ["pending", "failed"]);
        if (error) throw error;
      }
      const { error: eventError } = await admin.from("pos_payment_events").insert({
        stripe_event_id: event.id, organization_id: organizationId, sale_id: saleId, event_type: event.type,
      });
      if (eventError && eventError.code !== "23505") throw eventError;
      return Response.json({ received: true, payment: "pos" });
    }

    // Stripe retries are expected. A recorded event is acknowledged without
    // replaying side effects. Events are inserted only after successful processing.
    const { data: processed, error: lookupError } = await admin
      .from("subscription_billing_events")
      .select("id")
      .eq("stripe_event_id", event.id)
      .maybeSingle();
    if (lookupError) throw lookupError;
    if (processed) return Response.json({ received: true, duplicate: true });

    let subscription: any = null;
    let checkoutSession: any = null;
    let orgId: string | null = null;

    if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
      checkoutSession = object;
      orgId = object.metadata?.organization_id ?? object.client_reference_id ?? null;
      if (!orgId || object.client_reference_id !== orgId || object.metadata?.organization_id !== orgId) {
        throw new Error("Checkout session organization metadata mismatch");
      }

      if (object.mode === "payment") {
        if (object.payment_status !== "paid") {
          // Do not grant lifetime entitlement for unpaid/processing sessions.
          const { error } = await admin.from("subscription_billing_events").insert({
            stripe_event_id: event.id, event_type: event.type, organization_id: orgId,
            payload: { id: event.id, type: event.type, created: event.created, checkout_status: object.payment_status },
          });
          if (error && error.code !== "23505") throw error;
          return Response.json({ received: true, entitlement: "not_granted" });
        }
        if (object.metadata?.plan_id !== "lifetime") throw new Error("Unexpected one-time payment plan");
        const { data: plan, error: planError } = await admin.from("subscription_plans")
          .select("stripe_lifetime_price_id").eq("id", "lifetime").single();
        if (planError) throw planError;

        const { data: current } = await admin.from("organization_subscriptions")
          .select("metadata").eq("organization_id", orgId).maybeSingle();
        const metadata = {
          ...(current?.metadata ?? {}),
          license_type: "lifetime",
          scope: "per_store",
          updates: "lifetime",
          checkout_session_id: object.id,
          stripe_event_created: event.created,
          purchased_at: new Date(event.created * 1000).toISOString(),
        };
        const { error } = await admin.from("organization_subscriptions").upsert({
          organization_id: orgId, plan_id: "lifetime", billing_interval: "lifetime",
          status: "active", plan_type: "lifetime", stripe_customer_id: object.customer ?? null,
          stripe_subscription_id: null, stripe_price_id: plan?.stripe_lifetime_price_id ?? null,
          current_period_start: new Date(event.created * 1000).toISOString(),
          current_period_end: null, trial_ends_at: null, cancel_at_period_end: false,
          canceled_at: null, metadata, updated_at: new Date().toISOString(),
        }, { onConflict: "organization_id" });
        if (error) throw error;
        const { error: orgError } = await admin.from("organizations").update({ plan_type: "lifetime" }).eq("id", orgId);
        if (orgError) throw orgError;
      } else if (object.mode === "subscription" && object.subscription) {
        subscription = await stripeGet(`subscriptions/${object.subscription}`, stripeSecret);
        // The current Stripe object is fetched, rather than trusting a potentially stale event snapshot.
      }
    }

    if (event.type.startsWith("customer.subscription.") && object.id) {
      subscription = await stripeGet(`subscriptions/${object.id}`, stripeSecret);
    }

    if (event.type.startsWith("invoice.") && object.customer) {
      const { data: row, error } = await admin.from("organization_subscriptions")
        .select("stripe_subscription_id").eq("stripe_customer_id", object.customer).maybeSingle();
      if (error) throw error;
      if (row?.stripe_subscription_id) subscription = await stripeGet(`subscriptions/${row.stripe_subscription_id}`, stripeSecret);
    }

    if (subscription) {
      orgId = subscription.metadata?.organization_id ?? orgId;
      const planId = subscription.metadata?.plan_id;
      if (orgId && planId) {
        const item = subscription.items?.data?.[0];
        const status = subscription.status === "active" ? "active"
          : subscription.status === "trialing" ? "trialing"
          : subscription.status === "past_due" ? "past_due"
          : subscription.status === "canceled" ? "canceled"
          : subscription.status === "paused" ? "paused" : "incomplete";
        const { data: current } = await admin.from("organization_subscriptions")
          .select("metadata").eq("organization_id", orgId).maybeSingle();
        const metadata = {
          ...(current?.metadata ?? {}),
          stripe_event_created: Math.max(Number(current?.metadata?.stripe_event_created ?? 0), Number(event.created ?? 0)),
          ...(checkoutSession?.id ? { checkout_session_id: checkoutSession.id } : {}),
        };
        const { error } = await admin.from("organization_subscriptions").upsert({
          organization_id: orgId, plan_id: planId,
          billing_interval: subscription.metadata?.billing_interval ?? "month",
          status, plan_type: "subscription", stripe_customer_id: subscription.customer,
          stripe_subscription_id: subscription.id, stripe_price_id: item?.price?.id ?? null,
          current_period_start: subscription.current_period_start ? new Date(subscription.current_period_start * 1000).toISOString() : null,
          current_period_end: subscription.current_period_end ? new Date(subscription.current_period_end * 1000).toISOString() : null,
          trial_ends_at: subscription.trial_end ? new Date(subscription.trial_end * 1000).toISOString() : null,
          cancel_at_period_end: Boolean(subscription.cancel_at_period_end || subscription.cancel_at),
          canceled_at: subscription.canceled_at ? new Date(subscription.canceled_at * 1000).toISOString() : null,
          metadata, updated_at: new Date().toISOString(),
        }, { onConflict: "organization_id" });
        if (error) throw error;
        const { error: orgError } = await admin.from("organizations").update({ plan_type: "subscription" }).eq("id", orgId);
        if (orgError) throw orgError;
      }
    }

    const { error: eventError } = await admin.from("subscription_billing_events").insert({
      stripe_event_id: event.id,
      event_type: event.type,
      organization_id: orgId,
      payload: { id: event.id, type: event.type, created: event.created, livemode: event.livemode },
    });
    if (eventError && eventError.code !== "23505") throw eventError;
    return Response.json({ received: true });
  } catch (error) {
    return new Response(error instanceof Error ? error.message : "Webhook error", { status: 500 });
  }
});

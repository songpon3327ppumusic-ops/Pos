import { createClient } from "npm:@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "https://songpon3327ppumusic-ops.github.io", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });
Deno.serve(async (req) => {
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 if(req.method!=="POST") return json({error:"Method not allowed"},405);
 try {
  const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");
  if(!token) return json({error:"Authentication required"},401);
  const url=Deno.env.get("SUPABASE_URL")!, anon=Deno.env.get("SUPABASE_ANON_KEY")!, service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, stripeKey=Deno.env.get("STRIPE_SECRET_KEY");
  if(!stripeKey) return json({error:"Billing is not configured: STRIPE_SECRET_KEY is missing"},503);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:`Bearer ${token}`}}});
  const {data:{user},error:authError}=await userClient.auth.getUser(token);
  if(authError||!user) return json({error:"Invalid session"},401);
  const {organization_id,plan_id,billing_interval}=await req.json();
  if(!organization_id||!["starter","pro","business","lifetime"].includes(plan_id)||!(plan_id==="lifetime"?billing_interval==="lifetime":["month","year"].includes(billing_interval))) return json({error:"Invalid organization, plan, or billing interval"},400);
  const admin=createClient(url,service);
  const {data:member}=await admin.from("organization_members").select("role,is_active").eq("organization_id",organization_id).eq("user_id",user.id).maybeSingle();
  if(!member?.is_active||!["owner","admin"].includes(member.role)) return json({error:"Only the store owner or admin can manage billing"},403);
  const {data:plan}=await admin.from("subscription_plans").select("*").eq("id",plan_id).eq("is_active",true).single();
  const priceId=plan_id==="lifetime"?plan?.stripe_lifetime_price_id:billing_interval==="year"?plan?.stripe_yearly_price_id:plan?.stripe_monthly_price_id;
  if(!plan||!priceId) return json({error:"This plan is not ready for checkout yet"},409);
  const {data:org}=await admin.from("organizations").select("name").eq("id",organization_id).single();
  const {data:current}=await admin.from("organization_subscriptions").select("*").eq("organization_id",organization_id).maybeSingle();
  let customerId=current?.stripe_customer_id;
  if(!customerId){
   const cf=new URLSearchParams();cf.set("email",user.email??"");cf.set("name",org?.name??"StoreFlow customer");cf.set("metadata[organization_id]",organization_id);cf.set("metadata[supabase_user_id]",user.id);
   const cr=await fetch("https://api.stripe.com/v1/customers",{method:"POST",headers:{Authorization:`Bearer ${stripeKey}`,"Content-Type":"application/x-www-form-urlencoded"},body:cf});
   const customer=await cr.json();if(!cr.ok)return json({error:customer.error?.message??"Could not create Stripe customer"},502);
   customerId=customer.id;await admin.from("organization_subscriptions").upsert({organization_id,plan_id:"free",billing_interval:"month",status:"free",stripe_customer_id:customerId},{onConflict:"organization_id"});
  }
  const form=new URLSearchParams();form.set("mode",plan_id==="lifetime"?"payment":"subscription");form.set("customer",customerId);form.set("line_items[0][price]",priceId);form.set("line_items[0][quantity]","1");form.set("success_url","https://songpon3327ppumusic-ops.github.io/Pos/?billing=success&session_id={CHECKOUT_SESSION_ID}");form.set("cancel_url","https://songpon3327ppumusic-ops.github.io/Pos/?billing=cancel");form.set("allow_promotion_codes","true");form.set("client_reference_id",organization_id);form.set("metadata[organization_id]",organization_id);form.set("metadata[plan_id]",plan_id);form.set("metadata[billing_interval]",billing_interval);if(plan_id==="lifetime"){form.set("payment_intent_data[metadata][organization_id]",organization_id);form.set("payment_intent_data[metadata][plan_id]",plan_id);form.set("payment_intent_data[metadata][billing_interval]",billing_interval);}else{form.set("subscription_data[metadata][organization_id]",organization_id);form.set("subscription_data[metadata][plan_id]",plan_id);form.set("subscription_data[metadata][billing_interval]",billing_interval);form.set("subscription_data[billing_mode][type]","flexible");}
  const response=await fetch("https://api.stripe.com/v1/checkout/sessions",{method:"POST",headers:{Authorization:`Bearer ${stripeKey}`,"Content-Type":"application/x-www-form-urlencoded"},body:form});const session=await response.json();if(!response.ok)return json({error:session.error?.message??"Checkout creation failed"},502);return json({url:session.url});
 }catch(e){return json({error:e instanceof Error?e.message:"Unexpected error"},500);}
});
import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"https://songpon3327ppumusic-ops.github.io","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}});
async function stripeRequest(path:string,key:string,body?:URLSearchParams,method="POST"){
 const response=await fetch("https://api.stripe.com/v1/"+path,{method,headers:{Authorization:"Bearer "+key,...(body?{"Content-Type":"application/x-www-form-urlencoded"}:{})},body:body?.toString()});
 const data=await response.json();if(!response.ok)throw new Error(data.error?.message||"Stripe API error");return data;
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");
  if(!token)return json({error:"Authentication required"},401);
  const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,stripeKey=Deno.env.get("STRIPE_SECRET_KEY");
  if(!stripeKey)return json({error:"Stripe is not configured on this platform"},503);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}}});
  const {data:{user},error:authError}=await userClient.auth.getUser(token);
  if(authError||!user)return json({error:"Invalid session"},401);
  const {organization_id,action}=await req.json();
  if(!organization_id||!["onboard","status"].includes(action))return json({error:"Invalid request"},400);
  const admin=createClient(url,service);
  const {data:member}=await admin.from("organization_members").select("role,is_active,membership_status").eq("organization_id",organization_id).eq("user_id",user.id).maybeSingle();
  if(!member?.is_active||member.membership_status!=="active"||member.role!=="owner")return json({error:"Only the active store owner can connect Stripe"},403);
  const {data:org}=await admin.from("organizations").select("name").eq("id",organization_id).single();
  const {data:settings}=await admin.from("store_payment_settings").select("*").eq("organization_id",organization_id).maybeSingle();
  if(action==="onboard"){
   let accountId=settings?.stripe_connect_account_id;
   if(!accountId){
    const body=new URLSearchParams();body.set("type","express");body.set("country","TH");body.set("email",user.email||"");body.set("business_type","individual");
    body.set("capabilities[card_payments][requested]","true");body.set("capabilities[transfers][requested]","true");
    body.set("metadata[organization_id]",organization_id);body.set("metadata[store_name]",org?.name||"StoreFlow");
    const account=await stripeRequest("accounts",stripeKey,body);accountId=account.id;
    const {error}=await admin.from("store_payment_settings").upsert({organization_id,stripe_connect_account_id:accountId,stripe_enabled:false,stripe_charges_enabled:false,stripe_payouts_enabled:false,stripe_webhook_verified:false,updated_at:new Date().toISOString()},{onConflict:"organization_id"});
    if(error)throw error;
   }
   const link=new URLSearchParams();link.set("account",accountId);link.set("refresh_url","https://songpon3327ppumusic-ops.github.io/Pos/?stripe_connect=refresh");link.set("return_url","https://songpon3327ppumusic-ops.github.io/Pos/?stripe_connect=return");link.set("type","account_onboarding");
   const accountLink=await stripeRequest("account_links",stripeKey,link);
   return json({url:accountLink.url,account_id:accountId});
  }
  if(!settings?.stripe_connect_account_id)return json({connected:false,charges_enabled:false,webhook_verified:false});
  const account=await stripeRequest("accounts/"+settings.stripe_connect_account_id,stripeKey,undefined,"GET");
  const endpoints=await stripeRequest("webhook_endpoints?limit=100",stripeKey,undefined,"GET");
  const webhookUrl=url+"/functions/v1/storeflow-stripe-webhook";
  const requiredConnectEvents=["checkout.session.completed","checkout.session.async_payment_succeeded","checkout.session.async_payment_failed","checkout.session.expired"];
  const webhook=(endpoints.data||[]).find((x:any)=>x.url===webhookUrl&&x.connect===true&&x.status==="enabled"&&requiredConnectEvents.every((event:string)=>(x.enabled_events||[]).includes("*")||(x.enabled_events||[]).includes(event)));
  const charges=Boolean(account.charges_enabled),payouts=Boolean(account.payouts_enabled),webhookVerified=Boolean(webhook);
  const {error}=await admin.from("store_payment_settings").update({stripe_charges_enabled:charges,stripe_payouts_enabled:payouts,stripe_webhook_verified:webhookVerified,updated_at:new Date().toISOString()}).eq("organization_id",organization_id);
  if(error)throw error;
  return json({connected:true,account_id:account.id,charges_enabled:charges,payouts_enabled:payouts,webhook_verified:webhookVerified,details_submitted:Boolean(account.details_submitted)});
 }catch(error){return json({error:error instanceof Error?error.message:"Stripe Connect error"},500);}
});
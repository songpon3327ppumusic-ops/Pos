import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"https://songpon3327ppumusic-ops.github.io","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}});
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");if(!token)return json({error:"Authentication required"},401);
  const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,key=Deno.env.get("STRIPE_SECRET_KEY");
  if(!key)return json({error:"Stripe is not configured"},503);
  const client=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}}});const {data:{user}}=await client.auth.getUser(token);if(!user)return json({error:"Invalid session"},401);
  const {organization_id,sale_id}=await req.json();if(!organization_id||!sale_id)return json({error:"Missing organization or sale"},400);
  const admin=createClient(url,service);
  const {data:member}=await admin.from("organization_members").select("role,is_active,membership_status").eq("organization_id",organization_id).eq("user_id",user.id).maybeSingle();
  if(!member?.is_active||member.membership_status!=="active"||!["owner","admin","manager","cashier"].includes(member.role))return json({error:"Not authorized"},403);
  const {data:allowed,error:limitError}=await admin.rpc("consume_storeflow_rate_limit",{p_key:"pos-stripe-checkout:"+organization_id+":"+sale_id+":"+user.id,p_window_seconds:600,p_limit:5});
  if(limitError)throw limitError;if(allowed!==true)return json({error:"เริ่มชำระเงินผ่าน Stripe บ่อยเกินไป กรุณารอ 10 นาที"},429);
  const [{data:settings},{data:sale,saleError}]=await Promise.all([
   admin.from("store_payment_settings").select("stripe_connect_account_id,stripe_enabled,stripe_charges_enabled,stripe_webhook_verified").eq("organization_id",organization_id).maybeSingle(),
   admin.from("sales").select("id,receipt_no,total,payment_status,payment_method,stripe_checkout_session_id,payment_attempt").eq("organization_id",organization_id).eq("id",sale_id).single().then(({data,error})=>({data,saleError:error}))
  ]);
  if(!settings?.stripe_enabled||!settings.stripe_charges_enabled||!settings.stripe_webhook_verified||!settings.stripe_connect_account_id)return json({error:"ร้านยังเชื่อมต่อ Stripe Connect หรือ Webhook ไม่ครบ"},409);
  if(saleError||!sale||!["pending","failed"].includes(sale.payment_status)||sale.payment_method!=="Stripe Online")return json({error:"ไม่พบรายการที่รอชำระผ่าน Stripe"},409);

  let expectedSessionId:string|null=sale.stripe_checkout_session_id||null;
  if(expectedSessionId){
   const existingResponse=await fetch("https://api.stripe.com/v1/checkout/sessions/"+encodeURIComponent(expectedSessionId),{
    headers:{Authorization:"Bearer "+key,"Stripe-Account":settings.stripe_connect_account_id}
   });
   const existing=await existingResponse.json();
   if(!existingResponse.ok)return json({error:existing.error?.message||"ตรวจสอบ Stripe Checkout เดิมไม่สำเร็จ"},502);
   if(existing.status==="open"&&existing.url)return json({url:existing.url,session_id:existing.id,reused:true});
   if(existing.status==="complete")return json({error:"รายการ Stripe นี้ชำระแล้วหรือกำลังรอ Webhook ยืนยัน กรุณารีเฟรชประวัติการขาย"},409);
   if(existing.status!=="expired")return json({error:"สถานะ Stripe Checkout เดิมไม่รองรับการสร้างรายการใหม่"},409);
  }

  const {data:attempt,error:claimError}=await admin.rpc("claim_storeflow_pos_stripe_checkout",{
   p_organization_id:organization_id,p_sale_id:sale_id,p_user_id:user.id,p_expected_session_id:expectedSessionId
  });
  if(claimError||!Number.isInteger(attempt))return json({error:claimError?.message||"มีการเริ่มชำระเงินรายการนี้อยู่แล้ว กรุณารอสักครู่แล้วลองใหม่"},409);

  const amountMinor=Math.round(Number(sale.total)*100);
  if(!Number.isSafeInteger(amountMinor)||amountMinor<=0)return json({error:"ยอดขายไม่ถูกต้อง"},400);
  const form=new URLSearchParams();form.set("mode","payment");form.set("payment_method_types[0]","card");
  form.set("line_items[0][price_data][currency]","thb");form.set("line_items[0][price_data][unit_amount]",String(amountMinor));
  form.set("line_items[0][price_data][product_data][name]","StoreFlow · "+sale.receipt_no);form.set("line_items[0][quantity]","1");
  form.set("success_url","https://songpon3327ppumusic-ops.github.io/Pos/?stripe_payment=success&sale_id="+sale_id);
  form.set("cancel_url","https://songpon3327ppumusic-ops.github.io/Pos/?stripe_payment=cancel&sale_id="+sale_id);
  form.set("metadata[organization_id]",organization_id);form.set("metadata[sale_id]",sale_id);
  form.set("payment_intent_data[metadata][organization_id]",organization_id);form.set("payment_intent_data[metadata][sale_id]",sale_id);
  const response=await fetch("https://api.stripe.com/v1/checkout/sessions",{
   method:"POST",
   headers:{Authorization:"Bearer "+key,"Stripe-Account":settings.stripe_connect_account_id,"Content-Type":"application/x-www-form-urlencoded","Idempotency-Key":"storeflow-pos-"+sale_id+"-"+attempt},
   body:form.toString()
  });
  const session=await response.json();if(!response.ok)return json({error:session.error?.message||"Stripe Checkout failed"},502);
  const {data:saved,error:saveError}=await admin.from("sales").update({
   stripe_checkout_session_id:session.id,payment_status:"pending",status:"pending_payment"
  }).eq("id",sale_id).eq("organization_id",organization_id).eq("payment_attempt",attempt).select("id").maybeSingle();
  if(saveError||!saved)return json({error:"สร้าง Stripe Checkout แล้ว แต่บันทึกเลขอ้างอิงไม่สำเร็จ กรุณาติดต่อผู้ดูแลก่อนชำระเงิน"},500);
  return json({url:session.url,session_id:session.id});
 }catch(error){return json({error:error instanceof Error?error.message:"Stripe Checkout error"},500);}
});
"use client";
import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Activity, BarChart3, Bell, ChevronRight, CircleDollarSign, ClipboardList, Download, LayoutDashboard, LogOut, Menu, Package, Plus, Printer, Search, ShieldCheck, ShoppingCart, Store, UserRound, Users, Wallet, X } from "lucide-react";

type Page = "Dashboard" | "POS" | "Orders" | "Inventory" | "Customers" | "Employees" | "Expenses" | "Reports" | "Payroll" | "Permissions" | "Audit";
type Role = "owner" | "admin" | "manager" | "cashier" | "hr" | "accountant" | "employee";
type Product = { id:string; sku:string; name:string; category:string|null; cost:number; price:number; stock:number; min_stock:number; is_active:boolean };
type Customer = { id:string; full_name:string; phone:string|null; email:string|null; tier:string; points:number; credit_limit:number };
type Employee = { id:string; employee_code:string; full_name:string; position:string|null; department:string|null; phone:string|null; base_salary:number; is_active:boolean };
type Sale = { id:string; receipt_no:string; customer_id:string|null; subtotal:number; discount:number; tax:number; total:number; payment_method:string; status:string; created_at:string };
type Expense = { id:string; title:string; category:string; amount:number; expense_date:string; payment_status:string };
type SaleItem = { sale_id:string; quantity:number; unit_price:number; unit_cost:number; line_total:number };
const money=(n:number)=>new Intl.NumberFormat("th-TH",{style:"currency",currency:"THB",maximumFractionDigits:2}).format(n||0);
const dateText=(v:string)=>new Date(v).toLocaleString("th-TH",{dateStyle:"medium",timeStyle:"short"});
const nav:{id:Page;label:string;icon:any;group:string;roles:Role[]}[]=[
 {id:"Dashboard",label:"ภาพรวม",icon:LayoutDashboard,group:"หลัก",roles:["owner","admin","manager","cashier","employee"]},
 {id:"POS",label:"ขายหน้าร้าน (POS)",icon:ShoppingCart,group:"การขาย",roles:["owner","admin","manager","cashier"]},
 {id:"Orders",label:"รายการขาย",icon:ClipboardList,group:"การขาย",roles:["owner","admin","manager","cashier"]},
 {id:"Inventory",label:"สินค้าและสต็อก",icon:Package,group:"จัดการร้าน",roles:["owner","admin","manager"]},
 {id:"Customers",label:"ลูกค้า",icon:Users,group:"จัดการร้าน",roles:["owner","admin","manager","cashier"]},
 {id:"Employees",label:"พนักงาน",icon:UserRound,group:"บุคลากร",roles:["owner","admin","manager","hr"]},
 {id:"Expenses",label:"ค่าใช้จ่าย",icon:CircleDollarSign,group:"การเงิน",roles:["owner","admin","manager","accountant"]},
 {id:"Reports",label:"รายงาน",icon:BarChart3,group:"การเงิน",roles:["owner","admin","manager","accountant"]},
 {id:"Payroll",label:"เงินเดือน",icon:Wallet,group:"บุคลากร",roles:["owner","admin","manager","hr","accountant"]},
 {id:"Permissions",label:"สิทธิ์การใช้งาน",icon:ShieldCheck,group:"ตั้งค่า",roles:["owner","admin"]},
 {id:"Audit",label:"ประวัติการใช้งาน",icon:Activity,group:"ตั้งค่า",roles:["owner","admin","manager"]}
];
const roleNames:Record<Role,string>={owner:"เจ้าของร้าน",admin:"ผู้ดูแล",manager:"ผู้จัดการ",cashier:"แคชเชียร์",hr:"ฝ่ายบุคคล",accountant:"บัญชี",employee:"พนักงาน"};
function Card({children,className=""}:{children:React.ReactNode;className?:string}){return <section className={"rounded-2xl border border-slate-100 bg-white p-5 shadow-soft "+className}>{children}</section>}
function Empty({text}:{text:string}){return <div className="rounded-xl border border-dashed border-slate-200 p-10 text-center text-sm text-slate-400">{text}</div>}
export default function StoreApp(){
 const supabase=useMemo(()=>createClient(),[]);
 const [loading,setLoading]=useState(true),[loadError,setLoadError]=useState(""),[orgId,setOrgId]=useState(""),[orgName,setOrgName]=useState("StoreFlow"),[userEmail,setUserEmail]=useState(""),[role,setRole]=useState<Role>("employee");
 const [products,setProducts]=useState<Product[]>([]),[customers,setCustomers]=useState<Customer[]>([]),[employees,setEmployees]=useState<Employee[]>([]),[sales,setSales]=useState<Sale[]>([]),[saleItems,setSaleItems]=useState<SaleItem[]>([]),[expenses,setExpenses]=useState<Expense[]>([]),[audit,setAudit]=useState<any[]>([]);
 const [page,setPage]=useState<Page>("Dashboard"),[mobile,setMobile]=useState(false),[query,setQuery]=useState(""),[toast,setToast]=useState(""),[busy,setBusy]=useState(false);
 const [modal,setModal]=useState<"product"|"customer"|"employee"|"expense"|"stock"|"receipt"|null>(null),[record,setRecord]=useState<any>(null);
 const [form,setForm]=useState({name:"",sku:"",category:"ทั่วไป",price:"",cost:"",stock:"",phone:"",email:"",amount:"",position:"",department:""});
 const [cart,setCart]=useState<{id:string;qty:number}[]>([]),[payment,setPayment]=useState("เงินสด"),[discount,setDiscount]=useState("0"),[vat,setVat]=useState(false),[selectedCustomer,setSelectedCustomer]=useState("");
 const [stockDelta,setStockDelta]=useState(""),[stockNote,setStockNote]=useState("");
 const notify=(s:string)=>{setToast(s);window.setTimeout(()=>setToast(""),2600)};
 const field="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-100";
 const btn="inline-flex items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50";
 const reload=async(id=orgId)=>{
  if(!id)return;
  const results=await Promise.all([
   supabase.from("products").select("*").eq("organization_id",id).order("name"),
   supabase.from("customers").select("*").eq("organization_id",id).order("created_at",{ascending:false}),
   supabase.from("employees").select("*").eq("organization_id",id).order("created_at",{ascending:false}),
   supabase.from("sales").select("*").eq("organization_id",id).order("created_at",{ascending:false}).limit(500),
   supabase.from("sale_items").select("sale_id,quantity,unit_price,unit_cost,line_total").eq("organization_id",id),
   supabase.from("expenses").select("*").eq("organization_id",id).order("expense_date",{ascending:false}).limit(500),
   supabase.from("audit_logs").select("*").eq("organization_id",id).order("created_at",{ascending:false}).limit(100)
  ]);
  const failed=results.find(x=>x.error);
  if(failed?.error)throw failed.error;
  setProducts((results[0].data||[]) as Product[]);
  setCustomers((results[1].data||[]) as Customer[]);
  setEmployees((results[2].data||[]) as Employee[]);
  setSales((results[3].data||[]) as Sale[]);
  setSaleItems((results[4].data||[]) as SaleItem[]);
  setExpenses((results[5].data||[]) as Expense[]);
  setAudit(results[6].data||[]);
 };
 useEffect(()=>{
  let active=true;
  (async()=>{
   try{
    const {data:{session},error}=await supabase.auth.getSession();
    if(error)throw error;
    if(!session){window.location.replace("/Pos/login/");return;}
    if(!active)return;
    setUserEmail(session.user.email||"");
    let {data:membership,error:memberError}=await supabase.from("organization_members").select("organization_id,role").eq("user_id",session.user.id).eq("is_active",true).limit(1).maybeSingle();
    if(memberError)throw memberError;
    if(!membership){
     const {data:boot,error:bootError}=await supabase.rpc("bootstrap_store_owner",{p_org_slug:"storeflow"});
     if(bootError)throw bootError;
     const {data:created,error:createdError}=await supabase.from("organization_members").select("organization_id,role").eq("user_id",session.user.id).eq("is_active",true).limit(1).maybeSingle();
     if(createdError)throw createdError;
     membership=created;
     if(!membership && boot) membership={organization_id:boot,role:"owner"};
    }
    if(!membership)throw new Error("ไม่พบบัญชีร้านค้า กรุณาติดต่อเจ้าของร้านเพื่อขอสิทธิ์เข้าใช้งาน");
    if(!active)return;
    setOrgId(membership.organization_id);setRole(membership.role as Role);
    const {data:org,error:orgError}=await supabase.from("organizations").select("name").eq("id",membership.organization_id).maybeSingle();
    if(orgError)throw orgError;
    if(org?.name)setOrgName(org.name);
    await reload(membership.organization_id);
   }catch(e){if(active)setLoadError(e instanceof Error?e.message:"ไม่สามารถโหลดข้อมูลร้านค้าได้");}
   finally{if(active)setLoading(false);}
  })();
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,session)=>{if(!session)window.location.replace("/Pos/login/");});
  return ()=>{active=false;subscription.unsubscribe();};
 },[supabase]);
 const logout=async()=>{await supabase.auth.signOut();window.location.replace("/Pos/login/");};
 const visible=nav.filter(n=>n.roles.includes(role));
 const navigate=(p:Page)=>{setPage(p);setQuery("");setMobile(false)};
 const cartItems=cart.map(c=>{const p=products.find(x=>x.id===c.id);return p?{...p,qty:c.qty}:null}).filter(Boolean) as (Product&{qty:number})[];
 const subtotal=cartItems.reduce((s,p)=>s+p.price*p.qty,0),discountValue=Math.max(0,Number(discount)||0),taxValue=vat?Math.round(Math.max(0,subtotal-discountValue)*.07*100)/100:0,total=Math.max(0,subtotal-discountValue)+taxValue;
 const addToCart=(p:Product)=>{if(p.stock<=0){notify("สินค้าหมดสต็อก");return;}setCart(old=>{const item=old.find(x=>x.id===p.id);const next=item?old.map(x=>x.id===p.id?{...x,qty:x.qty+1}:x):[...old,{id:p.id,qty:1}];return next.map(x=>x.id===p.id?{...x,qty:Math.min(x.qty,p.stock)}:x);});};
 const openModal=(kind:NonNullable<typeof modal>,item?:any)=>{setRecord(item||null);setForm({name:item?.name||item?.full_name||item?.title||"",sku:item?.sku||"",category:item?.category||"ทั่วไป",price:item?String(item.price??""):"",cost:item?String(item.cost??""):"",stock:item?String(item.stock??""):"",phone:item?.phone||"",email:item?.email||"",amount:item?String(item.amount??""):"",position:item?.position||"",department:item?.department||""});setStockDelta("");setStockNote("");setModal(kind);};
 const saveRecord=async()=>{
  if(!orgId)return;setBusy(true);
  try{
   if(modal==="product"){
    const values={name:form.name.trim(),sku:form.sku.trim()||"SKU-"+Date.now(),category:form.category,cost:Number(form.cost)||0,price:Number(form.price)||0,is_active:true};
    if(!values.name)throw new Error("กรุณากรอกชื่อสินค้า");
    if(record){const {error}=await supabase.from("products").update(values).eq("id",record.id).eq("organization_id",orgId);if(error)throw error;}
    else{
     const {data,error}=await supabase.from("products").insert({...values,organization_id:orgId,stock:0,min_stock:0}).select("id").single();if(error)throw error;
     const initial=Number(form.stock)||0;
     if(initial>0){const {error:stockError}=await supabase.rpc("adjust_stock",{p_organization_id:orgId,p_product_id:data.id,p_quantity_delta:initial,p_note:"ยอดตั้งต้นสินค้า"});if(stockError)throw stockError;}
    }
   }else if(modal==="customer"){
    if(!form.name.trim())throw new Error("กรุณากรอกชื่อลูกค้า");
    const {error}=await supabase.from("customers").insert({organization_id:orgId,full_name:form.name.trim(),phone:form.phone||null,email:form.email||null});if(error)throw error;
   }else if(modal==="employee"){
    if(!form.name.trim())throw new Error("กรุณากรอกชื่อพนักงาน");
    const {error}=await supabase.from("employees").insert({organization_id:orgId,employee_code:"EMP-"+Date.now().toString().slice(-8),full_name:form.name.trim(),position:form.position||null,department:form.department||null,phone:form.phone||null,base_salary:0,is_active:true});if(error)throw error;
   }else if(modal==="expense"){
    if(!form.name.trim()||Number(form.amount)<=0)throw new Error("กรุณากรอกรายการและจำนวนเงินให้ถูกต้อง");
    const {error}=await supabase.from("expenses").insert({organization_id:orgId,title:form.name.trim(),category:form.category,amount:Number(form.amount),expense_date:new Date().toISOString().slice(0,10),payment_status:"paid"});if(error)throw error;
   }
   await reload();setModal(null);notify("บันทึกลงฐานข้อมูลจริงแล้ว");
  }catch(e){notify(e instanceof Error?e.message:"บันทึกไม่สำเร็จ");}
  finally{setBusy(false);}
 };
 const adjustStock=async()=>{
  if(!record||!Number(stockDelta))return;setBusy(true);
  try{const {error}=await supabase.rpc("adjust_stock",{p_organization_id:orgId,p_product_id:record.id,p_quantity_delta:Number(stockDelta),p_note:stockNote||"ปรับสต็อกโดยผู้ดูแล"});if(error)throw error;await reload();setModal(null);notify("ปรับสต็อกและบันทึกประวัติแล้ว");}
  catch(e){notify(e instanceof Error?e.message:"ปรับสต็อกไม่สำเร็จ");}finally{setBusy(false);}
 };
 const checkout=async()=>{
  if(!cartItems.length){notify("กรุณาเลือกสินค้าก่อน");return;}if(discountValue>subtotal){notify("ส่วนลดมากกว่ายอดสินค้า");return;}
  setBusy(true);
  try{
   const {data:saleId,error}=await supabase.rpc("checkout_sale",{p_organization_id:orgId,p_items:cartItems.map(p=>({product_id:p.id,quantity:p.qty})),p_payment_method:payment,p_discount:discountValue,p_tax:taxValue,p_customer_id:selectedCustomer||null});
   if(error)throw error;
   const {data:sale,error:saleError}=await supabase.from("sales").select("*").eq("id",saleId).single();if(saleError)throw saleError;
   await reload();setCart([]);setDiscount("0");setVat(false);setSelectedCustomer("");setRecord(sale);setModal("receipt");notify("บันทึกการขายและตัดสต็อกเรียบร้อย");
  }catch(e){notify(e instanceof Error?e.message:"ทำรายการขายไม่สำเร็จ");}
  finally{setBusy(false);}
 };
 const exportCsv=(name:string,rows:any[])=>{
  if(!rows.length){notify("ไม่มีข้อมูลสำหรับส่งออก");return;}
  const keys=Object.keys(rows[0]);const csv=[keys.join(","),...rows.map(r=>keys.map(k=>'"'+String(r[k]??"").replaceAll('"','""')+'"').join(","))].join("\n");
  const url=URL.createObjectURL(new Blob(["\ufeff"+csv],{type:"text/csv;charset=utf-8"}));const a=document.createElement("a");a.href=url;a.download=name+".csv";a.click();URL.revokeObjectURL(url);
 };
 const today=new Date();const todayKey=today.toISOString().slice(0,10);const monthKey=todayKey.slice(0,7);
 const todaySales=sales.filter(s=>s.created_at.slice(0,10)===todayKey&&s.status==="completed");
 const monthSales=sales.filter(s=>s.created_at.slice(0,7)===monthKey&&s.status==="completed");
 const grossProfit=saleItems.filter(i=>monthSales.some(s=>s.id===i.sale_id)).reduce((v,i)=>v+i.line_total-i.unit_cost*i.quantity,0);
 const monthExpense=expenses.filter(e=>e.expense_date.slice(0,7)===monthKey&&e.payment_status==="paid").reduce((v,e)=>v+e.amount,0);
 const salesByDay=Array.from({length:7},(_,i)=>{const d=new Date();d.setDate(d.getDate()-(6-i));const key=d.toISOString().slice(0,10);return {label:d.toLocaleDateString("th-TH",{weekday:"short"}),amount:sales.filter(s=>s.created_at.slice(0,10)===key&&s.status==="completed").reduce((v,s)=>v+s.total,0)};});
 const customerName=(id:string|null)=>customers.find(c=>c.id===id)?.full_name||"ลูกค้าทั่วไป";
 const pageTitle:Record<Page,string>={Dashboard:"ภาพรวมร้านค้า",POS:"ขายหน้าร้าน (POS)",Orders:"รายการขาย",Inventory:"สินค้าและสต็อก",Customers:"ลูกค้า",Employees:"พนักงาน",Expenses:"ค่าใช้จ่าย",Reports:"รายงาน",Payroll:"เงินเดือน",Permissions:"สิทธิ์การใช้งาน",Audit:"ประวัติการใช้งาน"};
 const title=(sub:string,action?:React.ReactNode)=><div className="mb-5 flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-xl font-bold">{pageTitle[page]}</h2><p className="mt-1 text-sm text-slate-500">{sub}</p></div>{action}</div>;
 const table=(heads:string[],rows:React.ReactNode[][])=><div className="overflow-x-auto rounded-xl border border-slate-100"><table className="w-full min-w-[650px] text-left"><thead className="bg-slate-50"><tr>{heads.map(h=><th key={h} className="px-4 py-3 text-xs font-semibold text-slate-400">{h}</th>)}</tr></thead><tbody className="divide-y divide-slate-100">{rows.map((row,i)=><tr key={i} className="hover:bg-slate-50/70">{row.map((cell,j)=><td key={j} className="px-4 py-3 text-sm text-slate-600">{cell}</td>)}</tr>)}</tbody></table></div>;
 const searchBox=<div className="relative mb-4"><Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"/><input className={field+" pl-9"} placeholder="ค้นหาข้อมูล..." value={query} onChange={e=>setQuery(e.target.value)}/></div>;
 const filteredProducts=products.filter(p=>(p.name+" "+p.sku+" "+(p.category||"")).toLowerCase().includes(query.toLowerCase()));
 const filteredSales=sales.filter(s=>(s.receipt_no+" "+customerName(s.customer_id)).toLowerCase().includes(query.toLowerCase()));
 const content=()=>{
  if(page==="Dashboard")return <div className="space-y-5">
   <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{[{label:"ยอดขายวันนี้",value:money(todaySales.reduce((v,s)=>v+s.total,0))},{label:"ยอดขายเดือนนี้",value:money(monthSales.reduce((v,s)=>v+s.total,0))},{label:"กำไรขั้นต้นเดือนนี้",value:money(grossProfit)},{label:"จำนวนบิลวันนี้",value:String(todaySales.length)}].map(x=><Card key={x.label}><p className="text-sm text-slate-500">{x.label}</p><p className="mt-2 text-2xl font-bold">{x.value}</p><p className="mt-2 text-xs text-slate-400">คำนวณจากข้อมูลที่บันทึกจริง</p></Card>)}</div>
   <div className="grid gap-5 xl:grid-cols-2"><Card><h3 className="mb-4 font-bold">ยอดขาย 7 วันล่าสุด</h3><div className="flex h-52 items-end gap-3 border-b border-slate-100 px-2">{salesByDay.map((d,i)=>{const max=Math.max(1,...salesByDay.map(x=>x.amount));return <div key={i} className="flex h-full flex-1 flex-col items-center justify-end gap-2"><div title={money(d.amount)} className="w-full rounded-t-md bg-emerald-500" style={{height:(d.amount/max*82)+"%"}}/><span className="text-xs text-slate-400">{d.label}</span></div>})}</div><p className="mt-3 text-xs text-slate-400">วันที่ไม่มียอดขายจะแสดงเป็นศูนย์</p></Card><Card><h3 className="mb-4 font-bold">สถานะร้านค้า</h3><div className="space-y-4"><div className="flex justify-between text-sm"><span>สินค้าในระบบ</span><b>{products.length} รายการ</b></div><div className="flex justify-between text-sm"><span>สินค้าใกล้หมด</span><b className="text-amber-600">{products.filter(p=>p.stock<=p.min_stock).length} รายการ</b></div><div className="flex justify-between text-sm"><span>ลูกค้า</span><b>{customers.length} ราย</b></div><div className="flex justify-between text-sm"><span>พนักงาน</span><b>{employees.length} คน</b></div><div className="flex justify-between text-sm"><span>ค่าใช้จ่ายเดือนนี้</span><b>{money(monthExpense)}</b></div></div></Card></div>
   <Card><div className="mb-4 flex items-center justify-between"><h3 className="font-bold">รายการขายล่าสุด</h3><button onClick={()=>navigate("Orders")} className="text-sm font-semibold text-emerald-700">ดูทั้งหมด <ChevronRight size={14} className="inline"/></button></div>{sales.length?table(["เลขที่ใบเสร็จ","ลูกค้า","ยอดสุทธิ","ช่องทางชำระ","เวลา"],sales.slice(0,5).map(s=>[<b>{s.receipt_no}</b>,customerName(s.customer_id),<b>{money(s.total)}</b>,s.payment_method,dateText(s.created_at)])):<Empty text="ยังไม่มีรายการขาย ข้อมูลจะปรากฏเมื่อมีการขายจริง"/>}</Card>
  </div>;
  if(page==="POS")return <div className="grid gap-5 xl:grid-cols-[1.5fr_1fr]"><div><div className="mb-4 flex items-center justify-between gap-3"><h3 className="font-bold">เลือกสินค้า ({products.length})</h3><div className="relative max-w-xs flex-1"><Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"/><input className={field+" pl-9"} placeholder="ค้นหาสินค้า..." value={query} onChange={e=>setQuery(e.target.value)}/></div></div>{filteredProducts.length?<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{filteredProducts.filter(p=>p.is_active).map(p=><button key={p.id} disabled={p.stock<=0} onClick={()=>addToCart(p)} className="rounded-2xl border border-slate-100 bg-white p-4 text-left shadow-soft hover:border-emerald-200 disabled:opacity-50"><div className="mb-3 flex h-16 items-center justify-center rounded-xl bg-emerald-50 text-2xl"><Package/></div><b className="text-sm">{p.name}</b><p className="mt-1 text-xs text-slate-400">{p.sku} · คงเหลือ {p.stock}</p><div className="mt-3 flex justify-between"><b className="text-emerald-700">{money(p.price)}</b><Plus size={17} className="text-emerald-600"/></div></button>)}</div>:<Empty text="ยังไม่มีสินค้า กรุณาเพิ่มสินค้าก่อนเริ่มขาย"/>}</div>
   <Card className="h-fit"><div className="mb-4 flex justify-between"><h3 className="font-bold">ตะกร้าสินค้า</h3><button onClick={()=>setCart([])} className="text-xs text-rose-500">ล้างตะกร้า</button></div>{cartItems.length?cartItems.map(p=><div key={p.id} className="flex items-center gap-2 border-b py-3"><div className="min-w-0 flex-1"><b className="text-sm">{p.name}</b><p className="text-xs text-slate-400">{money(p.price)}</p></div><button className="rounded bg-slate-100 px-2" onClick={()=>setCart(cs=>cs.map(c=>c.id===p.id?{...c,qty:Math.max(0,c.qty-1)}:c).filter(c=>c.qty>0))}>−</button><span className="text-sm">{p.qty}</span><button className="rounded bg-slate-100 px-2" onClick={()=>addToCart(p)}>+</button></div>):<Empty text="ยังไม่มีสินค้าในตะกร้า"/>}
   <div className="mt-4 space-y-3 text-sm"><label className="block text-xs text-slate-500">ลูกค้า<select className={field+" mt-1"} value={selectedCustomer} onChange={e=>setSelectedCustomer(e.target.value)}><option value="">ลูกค้าทั่วไป</option>{customers.map(c=><option key={c.id} value={c.id}>{c.full_name}</option>)}</select></label><div className="flex justify-between"><span>ยอดรวม</span><b>{money(subtotal)}</b></div><label className="flex items-center justify-between">ส่วนลด (บาท)<input type="number" min="0" max={subtotal} className="w-28 rounded-lg border px-2 py-1 text-right" value={discount} onChange={e=>setDiscount(e.target.value)}/></label><label className="flex justify-between">VAT 7%<input type="checkbox" checked={vat} onChange={e=>setVat(e.target.checked)}/></label><div className="flex justify-between border-t pt-3 text-base font-bold">ยอดชำระ <b className="text-emerald-700">{money(total)}</b></div><label className="block text-xs text-slate-500">วิธีชำระเงิน<select className={field+" mt-1"} value={payment} onChange={e=>setPayment(e.target.value)}><option>เงินสด</option><option>QR PromptPay</option><option>บัตรเครดิต/เดบิต</option><option>โอนเงิน</option></select></label><button disabled={busy||!cartItems.length} onClick={checkout} className={btn+" w-full justify-center py-3"}>{busy?"กำลังบันทึก...":"บันทึกการขายและตัดสต็อก"}</button><p className="text-xs leading-5 text-slate-400">ระบบบันทึกยอดขายและปรับสต็อกในธุรกรรมฐานข้อมูลเดียวกัน การเลือกวิธีชำระเงินเป็นการบันทึกประเภทการชำระ ไม่ใช่การตัดเงินจริงผ่านธนาคาร</p></div></Card></div>;
  if(page==="Inventory")return <>{title("จัดการสินค้าจากฐานข้อมูล",<button onClick={()=>openModal("product")} className={btn}><Plus size={16}/>เพิ่มสินค้า</button>)}{searchBox}{filteredProducts.length?table(["สินค้า / SKU","หมวดหมู่","ต้นทุน","ราคาขาย","คงเหลือ","จัดการ"],filteredProducts.map(p=>[<><b>{p.name}</b><p className="text-xs text-slate-400">{p.sku}</p></>,p.category||"ทั่วไป",money(p.cost),money(p.price),<b className={p.stock<=p.min_stock?"text-rose-600":""}>{p.stock}</b>,<button onClick={()=>openModal("stock",p)} className="rounded-lg border px-3 py-1.5 text-xs">ปรับสต็อก</button>])):<Empty text="ยังไม่มีสินค้าในฐานข้อมูล"/>}</>;
  if(page==="Orders")return <>{title("ประวัติการขายจริง",<button onClick={()=>exportCsv("storeflow-sales",sales)} className="rounded-xl border px-3 py-2 text-sm"><Download size={15} className="mr-1 inline"/>ส่งออก CSV</button>)}{searchBox}{filteredSales.length?table(["ใบเสร็จ","ลูกค้า","ยอดก่อนลด","ส่วนลด","ภาษี","ยอดสุทธิ","ชำระด้วย","เวลา"],filteredSales.map(s=>[<b>{s.receipt_no}</b>,customerName(s.customer_id),money(s.subtotal),money(s.discount),money(s.tax),<b>{money(s.total)}</b>,s.payment_method,dateText(s.created_at)])):<Empty text="ยังไม่มีรายการขาย"/>}</>;
  if(page==="Customers")return <>{title("ข้อมูลลูกค้าจริง",<button onClick={()=>openModal("customer")} className={btn}><Plus size={16}/>เพิ่มลูกค้า</button>)}{searchBox}{customers.length?table(["ชื่อลูกค้า","เบอร์โทร","อีเมล","ระดับสมาชิก","คะแนน"],customers.filter(c=>(c.full_name+" "+(c.phone||"")).toLowerCase().includes(query.toLowerCase())).map(c=>[<b>{c.full_name}</b>,c.phone||"-",c.email||"-",c.tier,c.points])):<Empty text="ยังไม่มีข้อมูลลูกค้า"/>}</>;
  if(page==="Employees")return <>{title("ทะเบียนพนักงานจริง",<button onClick={()=>openModal("employee")} className={btn}><Plus size={16}/>เพิ่มพนักงาน</button>)}{searchBox}{employees.length?table(["รหัส","ชื่อพนักงาน","ตำแหน่ง","แผนก","โทรศัพท์","สถานะ"],employees.filter(e=>(e.full_name+" "+e.employee_code).toLowerCase().includes(query.toLowerCase())).map(e=>[e.employee_code,<b>{e.full_name}</b>,e.position||"-",e.department||"-",e.phone||"-",e.is_active?"ปฏิบัติงาน":"ปิดใช้งาน"])):<Empty text="ยังไม่มีข้อมูลพนักงาน"/>}</>;
  if(page==="Expenses")return <>{title("ค่าใช้จ่ายที่บันทึกจริง",<button onClick={()=>openModal("expense")} className={btn}><Plus size={16}/>บันทึกค่าใช้จ่าย</button>)}{searchBox}{expenses.length?table(["รายการ","หมวดหมู่","วันที่","จำนวนเงิน","สถานะ"],expenses.filter(e=>(e.title+" "+e.category).toLowerCase().includes(query.toLowerCase())).map(e=>[<b>{e.title}</b>,e.category,e.expense_date,money(e.amount),e.payment_status])):<Empty text="ยังไม่มีค่าใช้จ่าย"/>}</>;
  if(page==="Reports")return <><div className="grid gap-4 sm:grid-cols-3"><Card><p className="text-sm text-slate-500">ยอดขายเดือนนี้</p><b className="mt-2 block text-2xl">{money(monthSales.reduce((v,s)=>v+s.total,0))}</b></Card><Card><p className="text-sm text-slate-500">ต้นทุนขายเดือนนี้</p><b className="mt-2 block text-2xl">{money(monthSales.reduce((v,s)=>v+s.subtotal,0)-grossProfit)}</b></Card><Card><p className="text-sm text-slate-500">ค่าใช้จ่ายเดือนนี้</p><b className="mt-2 block text-2xl">{money(monthExpense)}</b></Card></div><Card className="mt-5"><h3 className="mb-3 font-bold">สรุปรายการขายตามวันที่</h3>{table(["วันที่","จำนวนบิล","ยอดขาย"],salesByDay.map(d=>[d.label,sales.filter(s=>new Date(s.created_at).toLocaleDateString("th-TH",{weekday:"short"})===d.label).length,money(d.amount)]))}</Card></>;
  if(page==="Audit")return <>{title("กิจกรรมที่บันทึกในระบบ")}{audit.length?table(["กิจกรรม","ประเภท","รหัสรายการ","เวลา"],audit.map(a=>[a.action,a.entity_type,a.entity_id||"-",dateText(a.created_at)])):<Empty text="ยังไม่มีประวัติการใช้งาน"/>}</>;
  const unavailable:Record<string,string>={Payroll:"โมดูลเงินเดือนยังไม่เปิดใช้งานในฐานข้อมูลชุดนี้ จึงไม่แสดงตัวเลขจำลอง",Permissions:"การจัดการสิทธิ์รายโมดูลยังอยู่ระหว่างพัฒนา ขณะนี้ระบบใช้สิทธิ์ตามบทบาทที่กำหนดในฐานข้อมูล"};
  return <Card><h3 className="font-bold">{pageTitle[page]}</h3><p className="mt-2 text-sm text-slate-500">{unavailable[page]||"โมดูลนี้ยังไม่เปิดใช้งาน"}</p></Card>;
 };
 if(loading)return <main className="flex min-h-screen items-center justify-center bg-slate-50 text-sm text-slate-500">กำลังเชื่อมต่อฐานข้อมูล StoreFlow...</main>;
 if(loadError)return <main className="flex min-h-screen items-center justify-center bg-slate-50 p-5"><Card className="max-w-lg"><h1 className="text-lg font-bold text-rose-700">ไม่สามารถเปิดร้านค้าได้</h1><p className="mt-3 text-sm leading-6 text-slate-600">{loadError}</p><p className="mt-3 text-xs text-slate-400">ตรวจสอบการยืนยันอีเมล การเป็นสมาชิกของร้าน และฟังก์ชันฐานข้อมูล bootstrap_store_owner</p><button onClick={()=>window.location.reload()} className={btn+" mt-4"}>ลองอีกครั้ง</button></Card></main>;
 const groups=[...new Set(visible.map(n=>n.group))];
 return <div className="min-h-screen bg-slate-50"><aside className={"fixed inset-y-0 left-0 z-40 flex w-[260px] flex-col border-r border-slate-100 bg-white transition-transform lg:translate-x-0 "+(mobile?"translate-x-0":"-translate-x-full")}><div className="flex h-[76px] items-center gap-3 border-b px-6"><div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-600 text-white"><Store/></div><div><p className="text-lg font-extrabold">Store<span className="text-emerald-600">Flow</span></p><p className="max-w-[150px] truncate text-[10px] tracking-wide text-slate-400">{orgName}</p></div><button onClick={()=>setMobile(false)} className="ml-auto lg:hidden"><X/></button></div><nav className="mt-5 flex-1 space-y-5 overflow-y-auto px-3 pb-5">{groups.map(g=><div key={g}><p className="mb-2 px-3 text-[10px] font-bold uppercase tracking-[.16em] text-slate-400">{g}</p>{visible.filter(n=>n.group===g).map(n=><button key={n.id} onClick={()=>navigate(n.id)} className={"flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm "+(page===n.id?"bg-emerald-50 font-semibold text-emerald-700":"text-slate-500 hover:bg-slate-50")}><n.icon size={18}/>{n.label}</button>)}</div>)}</nav><div className="border-t p-4"><div className="flex items-center gap-2 rounded-xl bg-slate-50 p-3"><div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-sm font-bold text-emerald-700">{userEmail.slice(0,1).toUpperCase()}</div><div className="min-w-0 flex-1"><b className="block truncate text-xs">{userEmail}</b><p className="text-[10px] text-slate-400">{roleNames[role]}</p></div><button onClick={logout} title="ออกจากระบบ" className="rounded-lg p-2 text-slate-400 hover:bg-rose-50 hover:text-rose-600"><LogOut size={16}/></button></div></div></aside>
 {mobile&&<div onClick={()=>setMobile(false)} className="fixed inset-0 z-30 bg-slate-900/30 lg:hidden"/>}
 <main className="min-h-screen lg:ml-[260px]"><header className="sticky top-0 z-20 flex h-[76px] items-center justify-between border-b border-slate-100 bg-white/90 px-4 backdrop-blur md:px-8"><div className="flex items-center gap-3"><button onClick={()=>setMobile(true)} className="rounded-lg p-2 hover:bg-slate-100 lg:hidden"><Menu size={20}/></button><div><b className="text-sm">StoreFlow · {orgName}</b><p className="text-xs text-slate-400">{userEmail} · {roleNames[role]}</p></div></div><div className="flex items-center gap-2"><span className="rounded-lg bg-emerald-50 px-3 py-2 text-xs font-semibold text-emerald-700"><span className="mr-1 inline-block h-2 w-2 rounded-full bg-emerald-500"/>เชื่อมต่อฐานข้อมูลแล้ว</span><button onClick={()=>reload().then(()=>notify("อัปเดตข้อมูลแล้ว")).catch(e=>notify(e.message))} className="rounded-xl p-2 text-slate-500 hover:bg-slate-100" title="รีเฟรช"><Bell size={18}/></button></div></header><div className="mx-auto max-w-[1500px] p-4 md:p-8"><div className="mb-6"><p className="mb-1 text-xs text-slate-400">StoreFlow / <span className="text-emerald-700">{pageTitle[page]}</span></p><h1 className="text-2xl font-extrabold tracking-tight md:text-[28px]">{pageTitle[page]}</h1><p className="mt-1 text-sm text-slate-500">ข้อมูลทั้งหมดดึงจากฐานข้อมูลร้านค้าจริง</p></div>{content()}</div></main>
 {toast&&<div role="status" className="fixed bottom-5 right-5 z-[70] max-w-sm rounded-xl bg-slate-900 px-4 py-3 text-sm text-white shadow-xl">{toast}</div>}
 {modal&&<div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4" onMouseDown={e=>{if(e.target===e.currentTarget)setModal(null)}}><div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl"><div className="mb-5 flex items-center justify-between"><div><h3 className="text-lg font-bold">{modal==="product"?(record?"แก้ไขสินค้า":"เพิ่มสินค้า"):modal==="customer"?"เพิ่มลูกค้า":modal==="employee"?"เพิ่มพนักงาน":modal==="expense"?"บันทึกค่าใช้จ่าย":modal==="stock"?"ปรับสต็อกสินค้า":"ใบเสร็จรับเงิน"}</h3><p className="text-xs text-slate-400">บันทึกลง Supabase StoreFlow</p></div><button onClick={()=>setModal(null)}><X/></button></div>
 {modal==="receipt"?<div className="space-y-3"><div className="rounded-xl bg-slate-50 p-4 text-center"><b className="text-lg">{orgName}</b><p className="text-xs text-slate-400">ใบเสร็จรับเงิน / Receipt</p><p className="mt-3 font-mono text-sm">{record?.receipt_no}</p></div><div className="flex justify-between text-sm"><span>วันที่</span><b>{record?.created_at?dateText(record.created_at):"-"}</b></div><div className="flex justify-between text-sm"><span>ยอดสินค้า</span><b>{money(Number(record?.subtotal||0))}</b></div><div className="flex justify-between text-sm"><span>ส่วนลด</span><b>{money(Number(record?.discount||0))}</b></div><div className="flex justify-between border-t border-dashed pt-3"><b>ยอดสุทธิ</b><b className="text-xl text-emerald-700">{money(Number(record?.total||0))}</b></div><button onClick={()=>window.print()} className={btn+" w-full justify-center"}><Printer size={15}/>พิมพ์ใบเสร็จ</button></div>
 :modal==="stock"?<div className="space-y-3"><p className="text-sm">สินค้า: <b>{record?.name}</b> · คงเหลือ {record?.stock}</p><label className="block text-sm">จำนวนที่ปรับ (+ เพิ่ม / − ลด)<input type="number" step="0.001" className={field+" mt-1"} value={stockDelta} onChange={e=>setStockDelta(e.target.value)} placeholder="เช่น 10 หรือ -2"/></label><label className="block text-sm">หมายเหตุ<input className={field+" mt-1"} value={stockNote} onChange={e=>setStockNote(e.target.value)} placeholder="รับสินค้าเข้า / ตรวจนับสต็อก"/></label><button disabled={busy||!Number(stockDelta)} onClick={adjustStock} className={btn+" w-full justify-center"}>บันทึกการปรับสต็อก</button></div>
 :<div className="space-y-3"><label className="block text-sm font-medium">{modal==="product"?"ชื่อสินค้า":modal==="customer"?"ชื่อลูกค้า":modal==="employee"?"ชื่อพนักงาน":"รายการค่าใช้จ่าย"}<input required className={field+" mt-1"} value={form.name} onChange={e=>setForm(f=>({...f,name:e.target.value}))} placeholder="กรอกชื่อ"/></label>
 {modal==="product"&&<><div className="grid grid-cols-2 gap-3"><label className="text-sm">SKU<input className={field+" mt-1"} value={form.sku} onChange={e=>setForm(f=>({...f,sku:e.target.value}))} placeholder="สร้างอัตโนมัติได้"/></label><label className="text-sm">หมวดหมู่<select className={field+" mt-1"} value={form.category} onChange={e=>setForm(f=>({...f,category:e.target.value}))}><option>ทั่วไป</option><option>เครื่องดื่ม</option><option>อุปกรณ์</option><option>เบเกอรี่</option><option>วัตถุดิบ</option></select></label><label className="text-sm">ราคาทุน<input type="number" min="0" className={field+" mt-1"} value={form.cost} onChange={e=>setForm(f=>({...f,cost:e.target.value}))}/></label><label className="text-sm">ราคาขาย<input type="number" min="0" className={field+" mt-1"} value={form.price} onChange={e=>setForm(f=>({...f,price:e.target.value}))}/></label>{!record&&<label className="text-sm">สต็อกเริ่มต้น<input type="number" min="0" step="0.001" className={field+" mt-1"} value={form.stock} onChange={e=>setForm(f=>({...f,stock:e.target.value}))}/></label>}</div></>}
 {(modal==="customer"||modal==="employee")&&<><div className="grid grid-cols-2 gap-3"><label className="text-sm">เบอร์โทร<input className={field+" mt-1"} value={form.phone} onChange={e=>setForm(f=>({...f,phone:e.target.value}))}/></label>{modal==="customer"?<label className="text-sm">อีเมล<input type="email" className={field+" mt-1"} value={form.email} onChange={e=>setForm(f=>({...f,email:e.target.value}))}/></label>:<><label className="text-sm">ตำแหน่ง<input className={field+" mt-1"} value={form.position} onChange={e=>setForm(f=>({...f,position:e.target.value}))}/></label><label className="text-sm">แผนก<input className={field+" mt-1"} value={form.department} onChange={e=>setForm(f=>({...f,department:e.target.value}))}/></label></>}</div></>}
 {modal==="expense"&&<div className="grid grid-cols-2 gap-3"><label className="text-sm">จำนวนเงิน<input type="number" min="0.01" step="0.01" className={field+" mt-1"} value={form.amount} onChange={e=>setForm(f=>({...f,amount:e.target.value}))}/></label><label className="text-sm">หมวดหมู่<select className={field+" mt-1"} value={form.category} onChange={e=>setForm(f=>({...f,category:e.target.value}))}><option>ทั่วไป</option><option>ค่าเช่า</option><option>วัตถุดิบ</option><option>สาธารณูปโภค</option><option>เงินเดือน</option></select></label></div>}
 <div className="flex gap-2 pt-2"><button onClick={()=>setModal(null)} className="flex-1 rounded-xl border py-2.5 text-sm font-semibold">ยกเลิก</button><button disabled={busy} onClick={saveRecord} className={btn+" flex-1 justify-center"}>{busy?"กำลังบันทึก...":"บันทึกข้อมูล"}</button></div></div>}
 </div></div>}
 </div>;
}

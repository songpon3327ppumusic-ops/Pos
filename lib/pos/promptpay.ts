export function promptPayPayload(target:string,amount:number){
 const id=String(target||"").replace(/\\D/g,"");
 if(!/^0\\d{9}$/.test(id)&&!/^\\d{13}$/.test(id))throw new Error("กรุณาตั้งค่าเบอร์พร้อมเพย์ 10 หลักหรือเลขประจำตัว 13 หลัก");
 if(!Number.isFinite(amount)||amount<=0)throw new Error("ยอด QR ไม่ถูกต้อง");
 const proxy=/^0\\d{9}$/.test(id)?"0066"+id.slice(1):id;
 const tlv=(tag:string,value:string)=>tag+String(value.length).padStart(2,"0")+value;
 const merchant=tlv("00","A000000677010111")+tlv("01",proxy);
 let payload=tlv("00","01")+tlv("01","12")+tlv("29",merchant)+tlv("53","764")+tlv("54",amount.toFixed(2))+tlv("58","TH")+tlv("59","STOREFLOW")+tlv("60","BANGKOK")+"6304";
 let crc=0xffff;
 for(let i=0;i<payload.length;i++){crc^=payload.charCodeAt(i)<<8;for(let j=0;j<8;j++)crc=(crc&0x8000)?((crc<<1)^0x1021):(crc<<1);}
 return payload+(crc&0xffff).toString(16).toUpperCase().padStart(4,"0");
}

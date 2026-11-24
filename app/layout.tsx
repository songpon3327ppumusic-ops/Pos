import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "StoreFlow — All-in-One Store Management",
  description: "ระบบจัดการร้านค้าแบบครบวงจร"
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="th"><body>{children}</body></html>;
}
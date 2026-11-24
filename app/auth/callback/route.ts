import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  if (code) {
    const supabase = createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      const next = searchParams.get("next");
      return NextResponse.redirect(new URL(next && next.startsWith("/") && !next.startsWith("//") ? next : "/", origin));
    }
  }
  return NextResponse.redirect(new URL("/login?error=auth_callback", origin));
}
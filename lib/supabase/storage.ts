import { createClient } from "@/lib/supabase/client";

const ALLOWED_FOLDERS = new Set(["product-images", "store-logos", "employee-avatars"]);

function safeStorePath(organizationId: string, folder: string, fileName: string) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(organizationId)) {
    throw new Error("Invalid organization ID");
  }
  if (!ALLOWED_FOLDERS.has(folder)) throw new Error("Invalid asset folder");
  const safeName = fileName.normalize("NFKC").replace(/[^a-zA-Z0-9._-]/g, "_").slice(-100);
  return `${organizationId}/${folder}/${crypto.randomUUID()}-${safeName || "upload"}`;
}

/** Uploads to a private bucket. Storage RLS verifies current user's active membership. */
export async function uploadStoreAsset(organizationId: string, folder: string, file: File) {
  const supabase = createClient();
  const path = safeStorePath(organizationId, folder, file.name);
  const { data, error } = await supabase.storage.from("store-assets").upload(path, file, {
    upsert: false,
    contentType: file.type,
    cacheControl: "3600",
  });
  if (error) throw error;
  return { path: data.path };
}

/** Deletes only a file whose first path segment is the supplied organization ID. Storage RLS checks membership again. */
export async function deleteStoreAsset(organizationId: string, path: string) {
  if (!path.startsWith(`${organizationId}/`)) throw new Error("Asset does not belong to the active organization");
  const supabase = createClient();
  const { error } = await supabase.storage.from("store-assets").remove([path]);
  if (error) throw error;
}

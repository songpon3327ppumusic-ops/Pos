export type OfflineOrder = {
  idempotencyKey: string;
  organizationId: string;
  items: { product_id: string; quantity: number }[];
  paymentMethod: string;
  discount: number;
  tax: number;
  customerId: string | null;
  createdAt: string;
};

const DB_NAME = "storeflow-pos";
const DB_VERSION = 1;
const QUEUE = "offline_orders_queue";
const CATALOG = "product_catalog";

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === "undefined") return reject(new Error("IndexedDB is unavailable"));
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(QUEUE)) db.createObjectStore(QUEUE, { keyPath: "idempotencyKey" });
      if (!db.objectStoreNames.contains(CATALOG)) db.createObjectStore(CATALOG, { keyPath: "organizationId" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("Cannot open offline database"));
  });
}

export async function saveProductCatalog(organizationId: string, products: unknown[]) {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(CATALOG, "readwrite");
    tx.objectStore(CATALOG).put({ organizationId, products, savedAt: new Date().toISOString() });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

export async function readProductCatalog<T>(organizationId: string): Promise<T[]> {
  const db = await openDb();
  const result = await new Promise<T[]>((resolve, reject) => {
    const request = db.transaction(CATALOG, "readonly").objectStore(CATALOG).get(organizationId);
    request.onsuccess = () => resolve((request.result?.products || []) as T[]);
    request.onerror = () => reject(request.error);
  });
  db.close();
  return result;
}

export async function enqueueOfflineOrder(order: OfflineOrder) {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(QUEUE, "readwrite");
    tx.objectStore(QUEUE).put(order);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

export async function listOfflineOrders(): Promise<OfflineOrder[]> {
  const db = await openDb();
  const rows = await new Promise<OfflineOrder[]>((resolve, reject) => {
    const request = db.transaction(QUEUE, "readonly").objectStore(QUEUE).getAll();
    request.onsuccess = () => resolve((request.result || []) as OfflineOrder[]);
    request.onerror = () => reject(request.error);
  });
  db.close();
  return rows.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

export async function removeOfflineOrder(idempotencyKey: string) {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(QUEUE, "readwrite");
    tx.objectStore(QUEUE).delete(idempotencyKey);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

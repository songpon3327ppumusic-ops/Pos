# StoreFlow Android (Native)

This is the native Android application track for StoreFlow. It uses Kotlin and Jetpack Compose; it is not a WebView wrapper or a packaged copy of the Next.js website.

## Existing backend
- Supabase project ref: `tjunaxajcxwxirneopar`
- Keep existing Postgres schema, Auth users, RLS policies, Storage buckets and Edge Functions.
- Tenant isolation continues to use the existing `organization_id` membership model.
- Mobile clients must use only the Supabase publishable key. Never embed a service-role or secret key in the APK.

## Local setup
1. Open the `android` directory in Android Studio.
2. Use JDK 17 and Android SDK 36.
3. Create `android/local.properties` (never commit this file):
   ```properties
   sdk.dir=/path/to/Android/Sdk
   SUPABASE_URL=https://tjunaxajcxwxirneopar.supabase.co
   SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
   ```
4. Sync Gradle and run the `app` configuration on an emulator or Android device.

## Delivery phases
1. Native foundation and modern Compose navigation.
2. Supabase Auth, organization membership, role permissions and store switching.
3. Live dashboard, products, inventory and POS using existing database functions/RLS.
4. Offline queue and conflict-safe synchronization.
5. Camera barcode scanning, receipt printing and shift management.
6. Payment provider integration, Play Billing for eligible in-app digital subscriptions, privacy/Data Safety and Play release testing.

The initial UI deliberately shows placeholders instead of invented sales totals. Live business data is added only after authentication and organization access are implemented.

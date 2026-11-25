# Build StoreFlow APK / AAB with GitHub Actions

No local Android Studio installation is required. GitHub Actions builds on a hosted Ubuntu runner.

## 1. Add GitHub Actions secrets

Open repository Settings → Secrets and variables → Actions → New repository secret.

Required for live Supabase access:
- `SUPABASE_URL`: `https://tjunaxajcxwxirneopar.supabase.co`
- `SUPABASE_ANON_KEY`: legacy anon key, or preferably set `SUPABASE_PUBLISHABLE_KEY` to the project's publishable key.

The app uses only a public client key. Never add `service_role`, secret API keys, payment provider secrets or database passwords to an Android build.

## 2. Build a debug APK

Push a change under `android/` or open Actions → Build StoreFlow Android → Run workflow. The workflow generates the Gradle Wrapper on the hosted runner, runs `./gradlew assembleDebug`, and uploads `storeflow-debug-apk`.

Download the artifact ZIP from the completed workflow run, extract it, then install `app-debug.apk` on an Android device. Android may ask permission to install apps from the browser/file manager.

## 3. Create a release keystore (one time)

Run this on a trusted machine or secure shell environment with Java keytool:
```bash
keytool -genkeypair -v -keystore storeflow-release.jks -alias storeflow -keyalg RSA -keysize 4096 -validity 10000
base64 -w 0 storeflow-release.jks
```
Copy the base64 output and save it as GitHub secret `ANDROID_KEYSTORE_BASE64`. Also add:
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS` (for example `storeflow`)
- `ANDROID_KEY_PASSWORD`

Keep a secure offline backup of the keystore and passwords. Losing the signing key can prevent updating the same Play Store application. Never commit the keystore to Git.

## 4. Build a signed Play Store AAB

Open Actions → Build StoreFlow Android → Run workflow, enable `build_release`, and run it. The workflow builds `bundleRelease` and uploads `storeflow-release-aab`. Download the artifact ZIP and extract `app-release.aab` for Play Console.

## 5. Important current implementation status

The workflow and native Android project foundation are in place. The Kotlin app now has an initial Supabase email/password login and owner-signup screen, and calls the existing guarded bootstrap_store_owner RPC after login. Staff invitation/registration is not yet implemented because the app does not yet call a verified invite-redemption flow. Live dashboard, POS checkout, barcode camera flow, inventory, shifts/payroll and payment QR screens are still not connected to the production schema. Do not publish this starter build as a production POS app until those flows, RLS permissions, runtime permissions and real-device tests are complete.

The app manifest declares camera and Bluetooth permissions. Android 6+ and Android 12+ require runtime permission requests before accessing camera/Bluetooth hardware; declarations alone do not grant access.

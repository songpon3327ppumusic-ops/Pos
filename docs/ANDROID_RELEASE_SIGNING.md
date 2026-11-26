# StoreFlow Android Release Signing

The repository already contains `.github/workflows/release-aab.yml`. It builds a signed Android App Bundle after the four signing secrets and two Supabase build secrets are configured.

## GitHub repository secrets

Open **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Full contents of the supplied `ANDROID_KEYSTORE_BASE64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | From the supplied `STORE_SIGNING_CREDENTIALS.txt` |
| `ANDROID_KEY_ALIAS` | `storeflow` |
| `ANDROID_KEY_PASSWORD` | From the supplied `STORE_SIGNING_CREDENTIALS.txt` |
| `SUPABASE_URL` | The StoreFlow Supabase project URL |
| `SUPABASE_ANON_KEY` | The Supabase publishable/anon key (never the service_role key) |

Do not commit the keystore, base64 text, or passwords to Git.

## Build the release AAB

1. Open **Actions → StoreFlow Release AAB**.
2. Select **Run workflow** on branch `feature/android-native-storeflow`.
3. Leave **Upload to Google Play internal testing** unchecked until Play Console service-account access is configured.
4. Start the workflow and wait for **Build signed Android App Bundle** to succeed.
5. Download the `storeflow-release-aab` artifact and upload `app-release.aab` to Play Console.

## Signing key safety

Keep a secure offline backup of `storeflow-release.p12` and its passwords. Every future update to this Play app must use the same signing identity (or the configured Play App Signing upload-key reset process). Never generate a replacement key for an already-published app unless you intentionally rotate the upload key through Play Console.

Keystore type: PKCS12  
Alias: `storeflow`  
Certificate SHA-256: `0B:06:29:0E:3C:68:B9:0B:D6:DE:79:70:78:4B:33:28:0B:F3:84:E5:71:B3:36:99:B0:92:27:98:E6:16:66:E5`

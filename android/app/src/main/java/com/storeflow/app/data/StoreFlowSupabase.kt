package com.storeflow.app.data

import com.storeflow.app.BuildConfig
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.storage.Storage

object StoreFlowSupabase {
    val client by lazy {
        require(BuildConfig.SUPABASE_URL.isNotBlank()) {
            "Missing SUPABASE_URL. Configure GitHub Actions secrets."
        }
        require(BuildConfig.SUPABASE_ANON_KEY.isNotBlank()) {
            "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
        }
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY
        ) {
            install(Auth) { flowType = FlowType.PKCE; scheme = "storeflow"; host = "auth" }
            install(Postgrest)
            install(Realtime)
            install(Storage)
            install(Functions)
        }
    }
}

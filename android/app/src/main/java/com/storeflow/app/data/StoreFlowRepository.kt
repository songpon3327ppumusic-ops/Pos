package com.storeflow.app.data

import android.graphics.BitmapFactory

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import io.github.jan.supabase.functions.functions
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

@Serializable
data class PrivacyConsentInsert(
    @SerialName("user_id") val userId: String,
    @SerialName("consent_version") val consentVersion: String,
    @SerialName("terms_version") val termsVersion: String,
    @SerialName("privacy_policy_url") val privacyPolicyUrl: String
)

@Serializable
data class StoreMembership(
    @SerialName("organization_id") val organizationId: String,
    val role: String
)

@Serializable
data class StoreOrganization(
    val id: String,
    val name: String,
    val slug: String
)

@Serializable
data class StoreProduct(
    val id: String,
    val sku: String,
    val name: String,
    val category: String? = null,
    val price: Double,
    val stock: Double,
    @SerialName("min_stock") val minStock: Double = 0.0,
    val barcode: String? = null,
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class ProductInsert(
    @SerialName("organization_id") val organizationId: String,
    val sku: String,
    val name: String,
    val category: String? = null,
    val price: Double,
    val stock: Double = 0.0,
    @SerialName("min_stock") val minStock: Double = 0.0,
    val barcode: String? = null,
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class ProductUpdate(
    val sku: String,
    val name: String,
    val category: String? = null,
    val price: Double,
    @SerialName("min_stock") val minStock: Double,
    val barcode: String? = null
)

@Serializable
data class ProductArchiveUpdate(@SerialName("is_active") val isActive: Boolean = false)

@Serializable
data class StoreSaleSummary(
    val total: Double,
    @SerialName("created_at") val createdAt: String
)

data class StoreMetrics(
    val todaySales: Double = 0.0,
    val todayOrders: Int = 0,
    val lowStockCount: Int = 0
)


@Serializable
data class StoreEmployee(
    val id: String,
    @SerialName("employee_code") val employeeCode: String,
    @SerialName("full_name") val fullName: String,
    val position: String? = null,
    val department: String? = null,
    @SerialName("employment_type") val employmentType: String? = null,
    @SerialName("is_active") val isActive: Boolean = true,
    @SerialName("base_salary") val baseSalary: Double = 0.0,
    @SerialName("wage_rate") val wageRate: Double = 0.0,
    @SerialName("overtime_hourly_rate") val overtimeHourlyRate: Double = 0.0,
    @SerialName("position_allowance") val positionAllowance: Double = 0.0,
    @SerialName("regular_allowance") val regularAllowance: Double = 0.0,
    @SerialName("social_security_amount") val socialSecurityAmount: Double = 0.0
)

@Serializable
data class EmployeeInsert(
    @SerialName("organization_id") val organizationId: String,
    @SerialName("employee_code") val employeeCode: String,
    @SerialName("full_name") val fullName: String,
    val position: String? = null,
    val department: String? = null,
    @SerialName("employment_type") val employmentType: String = "permanent",
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class StoreShift(
    val id: String,
    @SerialName("employee_id") val employeeId: String,
    @SerialName("shift_date") val shiftDate: String,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
    @SerialName("shift_name") val shiftName: String,
    @SerialName("break_minutes") val breakMinutes: Int = 0,
    val notes: String? = null
)

@Serializable
data class ShiftInsert(
    @SerialName("organization_id") val organizationId: String,
    @SerialName("employee_id") val employeeId: String,
    @SerialName("shift_date") val shiftDate: String,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
    @SerialName("shift_name") val shiftName: String = "กะงาน",
    @SerialName("break_minutes") val breakMinutes: Int = 0,
    val notes: String? = null
)

@Serializable
data class AttendanceRecord(
    val id: String,
    @SerialName("employee_id") val employeeId: String,
    @SerialName("work_date") val workDate: String,
    @SerialName("clock_in") val clockIn: String? = null,
    @SerialName("clock_out") val clockOut: String? = null,
    @SerialName("worked_minutes") val workedMinutes: Int = 0,
    @SerialName("late_minutes") val lateMinutes: Int = 0,
    val status: String = "present"
)



@Serializable
data class StoreSubscription(
    val status: String,
    @SerialName("plan_id") val planId: String,
    @SerialName("trial_ends_at") val trialEndsAt: String? = null,
    @SerialName("current_period_end") val currentPeriodEnd: String? = null,
    @SerialName("plan_type") val planType: String = "subscription",
    @SerialName("plan_tier") val planTier: String = "basic"
)

@Serializable
data class StorePaymentSettings(
    @SerialName("organization_id") val organizationId: String,
    @SerialName("cash_enabled") val cashEnabled: Boolean = true,
    @SerialName("promptpay_enabled") val promptpayEnabled: Boolean = false,
    @SerialName("bank_transfer_enabled") val bankTransferEnabled: Boolean = false,
    @SerialName("promptpay_id") val promptpayId: String? = null,
    @SerialName("promptpay_name") val promptpayName: String? = null,
    @SerialName("bank_name") val bankName: String? = null,
    @SerialName("bank_account_name") val bankAccountName: String? = null,
    @SerialName("bank_account_number") val bankAccountNumber: String? = null,
    @SerialName("qr_image_path") val qrImagePath: String? = null,
    @SerialName("custom_qr_url") val customQrUrl: String? = null
)

@Serializable
data class StoreFlowPlatformSettings(
    val id: Boolean = true,
    @SerialName("custom_qr_url") val customQrUrl: String? = null,
    @SerialName("account_name") val accountName: String? = null,
    @SerialName("account_number") val accountNumber: String? = null,
    @SerialName("bank_name") val bankName: String? = null,
    @SerialName("promptpay_name") val promptpayName: String? = null,
    @SerialName("promptpay_id") val promptpayId: String? = null
)

@Serializable
data class StoreFlowPlanPaymentRequest(
    val id: String,
    @SerialName("organization_id") val organizationId: String,
    @SerialName("plan_tier") val planTier: String,
    @SerialName("billing_interval") val billingInterval: String,
    @SerialName("amount_thb") val amountThb: Double,
    val status: String,
    @SerialName("slip_path") val slipPath: String? = null,
    @SerialName("transaction_ref") val transactionRef: String? = null,
    @SerialName("created_at") val createdAt: String
)

class StoreFlowRepository(private val client: SupabaseClient) {

    suspend fun employees(organizationId: String): List<StoreEmployee> =
        client.from("employees").select {
            filter {
                eq("organization_id", organizationId)
                eq("is_active", true)
            }
            order("full_name", Order.ASCENDING)
            limit(300)
        }.decodeList()

    suspend fun addEmployee(
        organizationId: String,
        fullName: String,
        position: String,
        department: String,
        employmentType: String
    ) {
        require(fullName.isNotBlank()) { "กรุณากรอกชื่อพนักงาน" }
        val code = "SF-" + UUID.randomUUID().toString().take(8).uppercase()
        client.from("employees").insert(
            EmployeeInsert(
                organizationId = organizationId,
                employeeCode = code,
                fullName = fullName.trim(),
                position = position.trim().ifBlank { null },
                department = department.trim().ifBlank { null },
                employmentType = employmentType
            )
        )
    }

    suspend fun shifts(organizationId: String, shiftDate: String): List<StoreShift> =
        client.from("shifts").select {
            filter {
                eq("organization_id", organizationId)
                eq("shift_date", shiftDate)
            }
            order("starts_at", Order.ASCENDING)
            limit(300)
        }.decodeList()

    suspend fun scheduleShift(
        organizationId: String,
        employeeId: String,
        shiftDate: String,
        startTime: String,
        endTime: String,
        shiftName: String,
        breakMinutes: Int
    ) {
        val zone = ZoneId.of("Asia/Bangkok")
        val start = java.time.LocalDateTime.parse(
            "${shiftDate}T${startTime}"
        ).atZone(zone).toInstant().toString()
        val end = java.time.LocalDateTime.parse(
            "${shiftDate}T${endTime}"
        ).atZone(zone).toInstant().toString()
        require(java.time.Instant.parse(end).isAfter(java.time.Instant.parse(start))) {
            "เวลาเลิกกะต้องอยู่หลังเวลาเริ่มกะ"
        }
        require(breakMinutes in 0..480) { "เวลาพักไม่ถูกต้อง" }
        client.from("shifts").insert(
            ShiftInsert(
                organizationId = organizationId,
                employeeId = employeeId,
                shiftDate = shiftDate,
                startsAt = start,
                endsAt = end,
                shiftName = shiftName.ifBlank { "กะงาน" },
                breakMinutes = breakMinutes
            )
        )
    }

    suspend fun attendanceToday(organizationId: String, workDate: String): List<AttendanceRecord> =
        client.from("attendance").select {
            filter {
                eq("organization_id", organizationId)
                eq("work_date", workDate)
            }
            limit(500)
        }.decodeList()

    suspend fun clockIn(organizationId: String, shiftId: String): String {
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_shift_id", shiftId)
        }
        return client.postgrest.rpc("storeflow_clock_in", params).decodeAs<String>()
    }

    suspend fun clockOut(organizationId: String): String {
        val params = buildJsonObject { put("p_organization_id", organizationId) }
        return client.postgrest.rpc("storeflow_clock_out", params).decodeAs<String>()
    }


    suspend fun recordPrivacyConsent() {
        val userId = client.auth.currentUserOrNull()?.id ?: error("กรุณาเข้าสู่ระบบเพื่อบันทึกความยินยอม")
        client.from("privacy_consents").insert(PrivacyConsentInsert(
            userId = userId,
            consentVersion = "2026-11-26",
            termsVersion = "2026-11-26",
            privacyPolicyUrl = "https://benz-verse.com/storeflow-privacy"
        ))
    }

    suspend fun signUp(email: String, password: String) {
        require(email.contains("@") && password.length >= 8) { "กรอกอีเมลและรหัสผ่านอย่างน้อย 8 ตัวอักษร" }
        client.auth.signUpWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email.trim()
            this.password = password
        }
    }

    suspend fun createStore(storeName: String): String {
        val params = buildJsonObject { put("p_store_name", storeName.trim()) }
        return client.postgrest.rpc("storeflow_create_store", params).decodeAs<String>()
    }

    suspend fun joinStore(inviteCode: String): String {
        val params = buildJsonObject { put("p_invite_code", inviteCode.trim()) }
        return client.postgrest.rpc("storeflow_join_by_invite", params).decodeAs<String>()
    }

    suspend fun storePaymentSettings(organizationId: String): StorePaymentSettings? =
        client.from("store_payment_settings").select {
            filter { eq("organization_id", organizationId) }
            limit(1)
        }.decodeList<StorePaymentSettings>().firstOrNull()


    suspend fun uploadPlanSlip(requestId: String, bytes: ByteArray): String {
        require(bytes.isNotEmpty() && bytes.size <= 6 * 1024 * 1024) { "ไฟล์สลิปต้องมีขนาดไม่เกิน 6 MB" }
        val userId = client.auth.currentUserOrNull()?.id ?: error("กรุณาเข้าสู่ระบบใหม่")
        val extension = when {
            bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte() -> "jpg"
            bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(0x89.toByte(),0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)) -> "png"
            bytes.size >= 12 && String(bytes,0,4,Charsets.US_ASCII)=="RIFF" && String(bytes,8,4,Charsets.US_ASCII)=="WEBP" -> "webp"
            else -> error("รองรับเฉพาะ JPG, PNG หรือ WebP")
        }
        val path = "$userId/$requestId/slip.$extension"
        val mime = when(extension) { "jpg" -> "image/jpeg"; "png" -> "image/png"; else -> "image/webp" }
        client.storage.from("storeflow-platform-billing").upload(path, bytes) {
            contentType = io.ktor.http.ContentType.parse(mime)
        }
        return path
    }

    suspend fun uploadPlatformQr(bytes: ByteArray): String {
        require(bytes.isNotEmpty() && bytes.size <= 6 * 1024 * 1024) { "ไฟล์ QR ต้องมีขนาดไม่เกิน 6 MB" }
        val extension = when {
            bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte() -> "jpg"
            bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(0x89.toByte(),0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)) -> "png"
            bytes.size >= 12 && String(bytes,0,4,Charsets.US_ASCII)=="RIFF" && String(bytes,8,4,Charsets.US_ASCII)=="WEBP" -> "webp"
            else -> error("รองรับเฉพาะ JPG, PNG หรือ WebP")
        }
        val mime = when(extension) { "jpg" -> "image/jpeg"; "png" -> "image/png"; else -> "image/webp" }
        val path = "platform/qr/${UUID.randomUUID()}.$extension"
        client.storage.from("storeflow-platform-billing").upload(path, bytes) {
            contentType = io.ktor.http.ContentType.parse(mime)
        }
        return path
    }

    suspend fun downloadPlatformFile(path: String): ByteArray =
        client.storage.from("storeflow-platform-billing").downloadAuthenticated(path)

    suspend fun platformSettings(): StoreFlowPlatformSettings? =
        client.from("storeflow_platform_settings").select {
            filter { eq("id", true) }
            limit(1)
        }.decodeList<StoreFlowPlatformSettings>().firstOrNull()

    suspend fun savePlatformSettings(settings: StoreFlowPlatformSettings) {
        client.from("storeflow_platform_settings").upsert(settings) { onConflict = "id" }
    }

    suspend fun isPlatformAdmin(): Boolean =
        client.postgrest.rpc("storeflow_is_platform_admin").decodeAs<Boolean>()

    suspend fun submitPlanPayment(
        organizationId: String, planTier: String, interval: String,
        amount: Double, slipPath: String, transactionRef: String
    ): String {
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_plan_tier", planTier)
            put("p_billing_interval", interval)
            put("p_amount_thb", amount)
            put("p_slip_path", slipPath)
            put("p_transaction_ref", transactionRef)
        }
        return client.postgrest.rpc("storeflow_submit_plan_payment", params).decodeAs<String>()
    }

    suspend fun planPaymentRequests(organizationId: String): List<StoreFlowPlanPaymentRequest> =
        client.from("storeflow_plan_payment_requests").select {
            filter { eq("organization_id", organizationId) }
            order("created_at", Order.DESCENDING)
            limit(30)
        }.decodeList()

    suspend fun allPendingPlanPaymentRequests(): List<StoreFlowPlanPaymentRequest> =
        client.from("storeflow_plan_payment_requests").select {
            filter { eq("status", "pending_review") }
            order("created_at", Order.ASCENDING)
            limit(200)
        }.decodeList()

    suspend fun reviewPlanPayment(requestId: String, approve: Boolean, note: String? = null) {
        val params = buildJsonObject {
            put("p_request_id", requestId)
            put("p_approve", approve)
            if (note.isNullOrBlank()) put("p_admin_note", JsonNull) else put("p_admin_note", note)
        }
        client.postgrest.rpc("storeflow_review_plan_payment", params)
    }

    suspend fun saveStorePaymentSettings(settings: StorePaymentSettings) {
        require(client.auth.currentUserOrNull()?.id != null) { "กรุณาเข้าสู่ระบบใหม่" }
        val value = settings.copy(
            promptpayId = settings.promptpayId?.filter { it.isDigit() }?.ifBlank { null },
            promptpayName = settings.promptpayName?.trim()?.ifBlank { null },
            bankName = settings.bankName?.trim()?.ifBlank { null },
            bankAccountName = settings.bankAccountName?.trim()?.ifBlank { null },
            bankAccountNumber = settings.bankAccountNumber?.filter { it.isDigit() }?.ifBlank { null }
        )
        client.from("store_payment_settings").upsert(value) {
            onConflict = "organization_id"
        }
    }

    suspend fun updateEmployeeSalary(
        employeeId: String,
        baseSalary: Double,
        wageRate: Double,
        overtimeRate: Double,
        positionAllowance: Double,
        regularAllowance: Double,
        socialSecurity: Double
    ) {
        require(listOf(baseSalary, wageRate, overtimeRate, positionAllowance, regularAllowance, socialSecurity).all { it >= 0.0 }) {
            "จำนวนเงินต้องไม่ติดลบ"
        }
        client.from("employees").update({
            set("base_salary", baseSalary)
            set("wage_rate", wageRate)
            set("overtime_hourly_rate", overtimeRate)
            set("position_allowance", positionAllowance)
            set("regular_allowance", regularAllowance)
            set("social_security_amount", socialSecurity)
        }) {
            filter { eq("id", employeeId) }
        }
    }



    suspend fun exportStoreBackup(organizationId: String): String {
        val params = buildJsonObject { put("p_organization_id", organizationId) }
        return client.postgrest.rpc("storeflow_export_json", params).decodeAs<JsonElement>().toString()
    }

    suspend fun importStoreBackup(organizationId: String, jsonText: String): String {
        val backup = Json.parseToJsonElement(jsonText)
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_backup", backup)
        }
        return client.postgrest.rpc("storeflow_import_json", params).decodeAs<JsonElement>().toString()
    }

    suspend fun downloadStoreQr(path: String): ByteArray =
        client.storage.from("storeflow-store-assets").downloadAuthenticated(path)

    suspend fun uploadStoreQr(organizationId: String, bytes: ByteArray): String {
        require(bytes.isNotEmpty() && bytes.size <= 6 * 1024 * 1024) { "ไฟล์ QR ต้องมีขนาดไม่เกิน 6 MB" }
        val mime = when {
            bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte() ->
                "image/jpeg" to "jpg"
            bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(
                byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            ) -> "image/png" to "png"
            bytes.size >= 12 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" &&
                String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP" -> "image/webp" to "webp"
            else -> error("รองรับเฉพาะรูป QR แบบ JPG, PNG หรือ WebP")
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth in 1..4096 && bounds.outHeight in 1..4096) {
            "ขนาดรูป QR ไม่ถูกต้องหรือใหญ่เกินไป"
        }
        val path = "$organizationId/qr/${UUID.randomUUID()}.${mime.second}"
        client.storage.from("storeflow-store-assets").upload(path, bytes) {
            contentType = io.ktor.http.ContentType.parse(mime.first)
        }
        return path
    }

    suspend fun deleteAccountPermanently() {
        val body = buildJsonObject { put("confirm", "DELETE MY ACCOUNT") }
        client.functions.invoke("storeflow-delete-account", body = body)
    }

    suspend fun subscription(organizationId: String): StoreSubscription? =
        client.from("organization_subscriptions").select {
            filter { eq("organization_id", organizationId) }
            limit(1)
        }.decodeList<StoreSubscription>().firstOrNull()

    suspend fun ownerInviteCode(): String =
        client.postgrest.rpc("get_store_invite_code").decodeAs<String>()

    suspend fun signIn(email: String, password: String) {
        client.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signInWithGoogle() {
        // Explicit native callback: AndroidManifest + Supabase Auth URL allow-list must
        // both contain storeflow://auth so OAuth returns to the installed app.
        client.auth.signInWith(
            io.github.jan.supabase.auth.providers.Google,
            redirectUrl = "storeflow://auth"
        )
    }

    suspend fun signOut() {
        client.auth.signOut()
    }

    suspend fun activeMemberships(): List<StoreMembership> {
        val userId = client.auth.currentUserOrNull()?.id
            ?: error("กรุณาเข้าสู่ระบบใหม่")
        return client.from("organization_members").select {
            filter {
                eq("user_id", userId)
                eq("is_active", true)
                eq("membership_status", "active")
            }
            order("created_at", Order.ASCENDING)
        }.decodeList()
    }

    suspend fun organization(id: String): StoreOrganization {
        return client.from("organizations").select {
            filter { eq("id", id) }
            limit(1)
        }.decodeSingle()
    }

    suspend fun products(organizationId: String): List<StoreProduct> {
        return client.from("products").select {
            filter {
                eq("organization_id", organizationId)
                eq("is_active", true)
            }
            order("name", Order.ASCENDING)
            limit(300)
        }.decodeList()
    }

    suspend fun addProduct(
        organizationId: String,
        sku: String,
        name: String,
        category: String,
        price: Double,
        minStock: Double,
        initialStock: Double = 0.0,
        barcode: String? = null
    ) {
        require(sku.isNotBlank()) { "กรุณากรอกรหัสสินค้า" }
        require(name.isNotBlank()) { "กรุณากรอกชื่อสินค้า" }
        require(price >= 0) { "ราคาต้องไม่ติดลบ" }
        require(minStock >= 0 && initialStock >= 0) { "จำนวนสต็อกต้องไม่ติดลบ" }
        client.from("products").insert(
            ProductInsert(
                organizationId = organizationId,
                sku = sku.trim(),
                name = name.trim(),
                category = category.trim().ifBlank { null },
                price = price,
                stock = initialStock,
                minStock = minStock,
                barcode = barcode?.trim()?.ifBlank { null }
            )
        )
    }

    suspend fun updateProduct(organizationId: String, productId: String, sku: String, name: String,
        category: String, price: Double, minStock: Double, barcode: String?) {
        require(sku.isNotBlank() && name.isNotBlank()) { "กรุณากรอกรหัสและชื่อสินค้า" }
        require(price >= 0 && minStock >= 0) { "ราคาและจุดเตือนสต็อกต้องไม่ติดลบ" }
        client.from("products").update(ProductUpdate(
            sku = sku.trim(), name = name.trim(), category = category.trim().ifBlank { null },
            price = price, minStock = minStock, barcode = barcode?.trim()?.ifBlank { null }
        )) {
            filter { eq("id", productId); eq("organization_id", organizationId) }
        }
    }

    suspend fun archiveProduct(organizationId: String, productId: String) {
        client.from("products").update(ProductArchiveUpdate()) {
            filter { eq("id", productId); eq("organization_id", organizationId) }
        }
    }

    suspend fun adjustStock(organizationId: String, productId: String, delta: Double, note: String) {
        require(delta != 0.0) { "จำนวนปรับสต็อกต้องไม่เป็นศูนย์" }
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_product_id", productId)
            put("p_quantity_delta", delta)
            put("p_note", note.ifBlank { "ปรับสต็อกจากแอป StoreFlow" })
        }
        client.postgrest.rpc("adjust_stock", params)
    }

    suspend fun metrics(organizationId: String, productList: List<StoreProduct>): StoreMetrics {
        val start = LocalDate.now(ZoneId.of("Asia/Bangkok"))
            .atStartOfDay(ZoneId.of("Asia/Bangkok")).toInstant().toString()
        val sales = client.from("sales").select {
            filter {
                eq("organization_id", organizationId)
                gte("created_at", start)
                eq("status", "completed")
            }
            limit(1000)
        }.decodeList<StoreSaleSummary>()
        return StoreMetrics(
            todaySales = sales.sumOf { it.total },
            todayOrders = sales.size,
            lowStockCount = productList.count { it.stock <= it.minStock }
        )
    }


    suspend fun createPosSaleWithPayment(
        organizationId: String,
        items: List<Pair<StoreProduct, Double>>,
        paymentMethod: String,
        cashReceived: Double? = null
    ): String {
        require(items.isNotEmpty()) { "ตะกร้าสินค้าว่าง" }
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_items", buildJsonArray {
                items.forEach { (product, quantity) ->
                    add(buildJsonObject {
                        put("product_id", product.id)
                        put("quantity", quantity)
                    })
                }
            })
            put("p_payment_method", paymentMethod)
            put("p_discount", 0)
            put("p_tax", 0)
            put("p_customer_id", JsonNull)
            put("p_idempotency_key", UUID.randomUUID().toString())
            if (cashReceived == null) put("p_cash_received", JsonNull) else put("p_cash_received", cashReceived)
            put("p_amount_tendered", cashReceived ?: 0)
            put("p_payment_ref", JsonNull)
            put("p_slip_path", JsonNull)
            put("p_card_approval_code", JsonNull)
            put("p_card_last4", JsonNull)
        }
        return client.postgrest.rpc("create_pos_sale_with_payment", params).decodeAs<String>()
    }

    suspend fun uploadPosSlip(organizationId: String, saleId: String, bytes: ByteArray): String {
        require(bytes.isNotEmpty() && bytes.size <= 6 * 1024 * 1024) { "ไฟล์สลิปต้องมีขนาดไม่เกิน 6 MB" }
        val path = "$organizationId/slips/$saleId/slip.jpg"
        client.storage.from("storeflow-pos-slips").upload(path, bytes) {
            contentType = io.ktor.http.ContentType.Image.JPEG
        }
        return path
    }

    suspend fun attachPosSlip(organizationId: String, saleId: String, path: String, transactionRef: String) {
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_sale_id", saleId)
            put("p_slip_path", path)
            put("p_transaction_ref", transactionRef)
        }
        client.postgrest.rpc("storeflow_attach_pos_slip", params)
    }

    suspend fun reviewPosSlip(organizationId: String, saleId: String, approve: Boolean, transactionRef: String, note: String) {
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_sale_id", saleId)
            put("p_approve", approve)
            put("p_transaction_ref", transactionRef)
            put("p_note", note)
        }
        client.postgrest.rpc("owner_review_pos_slip", params)
    }

    suspend fun checkoutCash(
        organizationId: String,
        items: List<Pair<StoreProduct, Double>>,
        cashReceived: Double
    ): String {
        require(items.isNotEmpty()) { "ตะกร้าสินค้าว่าง" }
        val params = buildJsonObject {
            put("p_organization_id", organizationId)
            put("p_items", buildJsonArray {
                items.forEach { (product, quantity) ->
                    add(buildJsonObject {
                        put("product_id", product.id)
                        put("quantity", quantity)
                    })
                }
            })
            put("p_payment_method", "cash")
            put("p_discount", 0)
            put("p_tax", 0)
            put("p_customer_id", JsonNull)
            put("p_idempotency_key", UUID.randomUUID().toString())
            put("p_cash_received", cashReceived)
        }
        return client.postgrest.rpc("checkout_sale_idempotent", params).decodeAs<String>()
    }
}

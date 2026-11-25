package com.storeflow.app.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

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
    @SerialName("is_active") val isActive: Boolean = true
)

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
    @SerialName("is_active") val isActive: Boolean = true
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
            "$shiftDateT$startTime"
        ).atZone(zone).toInstant().toString()
        val end = java.time.LocalDateTime.parse(
            "$shiftDateT$endTime"
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

    suspend fun signIn(email: String, password: String) {
        client.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signInWithGoogle() {
        client.auth.signInWith(io.github.jan.supabase.auth.providers.Google)
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
        minStock: Double
    ) {
        require(sku.isNotBlank()) { "กรุณากรอกรหัสสินค้า" }
        require(name.isNotBlank()) { "กรุณากรอกชื่อสินค้า" }
        require(price >= 0) { "ราคาต้องไม่ติดลบ" }
        require(minStock >= 0) { "จุดเตือนสต็อกต้องไม่ติดลบ" }
        client.from("products").insert(
            ProductInsert(
                organizationId = organizationId,
                sku = sku.trim(),
                name = name.trim(),
                category = category.trim().ifBlank { null },
                price = price,
                minStock = minStock
            )
        )
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

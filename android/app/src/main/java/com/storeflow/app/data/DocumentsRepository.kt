package com.storeflow.app.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class BusinessDocument(
    val id: String,
    @SerialName("document_no") val documentNo: String,
    @SerialName("document_type") val documentType: String,
    val status: String,
    @SerialName("issue_date") val issueDate: String,
    @SerialName("due_date") val dueDate: String? = null,
    @SerialName("party_name") val partyName: String? = null,
    @SerialName("party_tax_id") val partyTaxId: String? = null,
    val subtotal: Double,
    @SerialName("tax_amount") val taxAmount: Double,
    val total: Double,
    val notes: String? = null,
    @SerialName("tax_mode") val taxMode: String = "exclude"
)

@Serializable
data class StoreBusinessHeader(
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("legal_name") val legalName: String? = null,
    val address: String? = null,
    @SerialName("tax_id") val taxId: String? = null,
    @SerialName("branch_code") val branchCode: String? = null,
    @SerialName("branch_name") val branchName: String? = null,
    @SerialName("logo_path") val logoPath: String? = null
)

data class DocumentLine(
    val description: String, val quantity: Double, val unit: String = "รายการ",
    val unitPrice: Double, val discount: Double = 0.0, val productId: String? = null
)

class DocumentsRepository(private val client: SupabaseClient) {
    suspend fun businessHeader(organizationId: String): StoreBusinessHeader? =
        client.from("organization_business_settings").select {
            filter { eq("organization_id", organizationId) }
            limit(1)
        }.decodeList<StoreBusinessHeader>().firstOrNull()

    suspend fun downloadBusinessLogo(path: String): ByteArray =
        client.storage.from("storeflow-store-assets").downloadAuthenticated(path)

    suspend fun list(organizationId: String): List<BusinessDocument> =
        client.from("business_documents").select {
            filter { eq("organization_id", organizationId) }
            order("created_at", Order.DESCENDING)
            limit(100)
        }.decodeList()

    suspend fun create(organizationId: String, type: String, partyName: String, partyTaxId: String,
        partyAddress: String, issueDate: String, dueDate: String?, lines: List<DocumentLine>,
        taxMode: String, taxRate: Double, notes: String, incomeType: String = "", withholdingRate: Double = 0.0): String {
        require(partyName.isNotBlank()) { "กรุณากรอกชื่อผู้ซื้อ/คู่ค้า" }
        require(lines.isNotEmpty() || type == "withholding_certificate") { "กรุณาเพิ่มรายการ" }
        require(lines.all { it.description.isNotBlank() && it.quantity > 0 && it.unitPrice >= 0 && it.discount >= 0 }) { "รายการไม่ถูกต้อง" }
        require(taxRate in 0.0..100.0) { "อัตราภาษีไม่ถูกต้อง" }
        val items = buildJsonArray { lines.forEach { line -> add(buildJsonObject {
            put("description", line.description); put("quantity", line.quantity); put("unit", line.unit)
            put("unit_price", line.unitPrice); put("discount", line.discount)
            line.productId?.let { put("product_id", it) }
        }) } }
        val metadata = buildJsonObject {
            put("tax_mode", taxMode)
            if (type == "withholding_certificate") {
                val base = lines.sumOf { it.quantity * it.unitPrice - it.discount }
                put("withholding", buildJsonObject {
                    put("income_type", incomeType); put("rate", withholdingRate)
                    put("withholding_tax", base * withholdingRate / 100.0)
                })
            }
        }
        val params = buildJsonObject {
            put("p_organization_id", organizationId); put("p_document_type", type)
            put("p_party_name", partyName.trim()); put("p_party_tax_id", partyTaxId.filter(Char::isDigit))
            put("p_party_address", partyAddress.trim()); put("p_issue_date", issueDate)
            dueDate?.takeIf { it.isNotBlank() }?.let { put("p_due_date", it) }
            put("p_items", items); put("p_discount", 0)
            put("p_tax_rate", if (taxMode == "non_vat") 0 else taxRate)
            put("p_notes", notes); put("p_metadata", metadata)
        }
        return client.postgrest.rpc("create_storeflow_business_document", params).decodeAs<String>()
    }
}
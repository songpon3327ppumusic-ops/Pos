package com.storeflow.app.billing

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.android.billingclient.api.*
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.put

/**
 * Client purchase callbacks never grant access directly. The purchase token is
 * submitted to a server-side verifier which must query Google Play Developer API.
 */
class StoreFlowBilling(context: Context, private val supabase: SupabaseClient,
    private val organizationId: String, private val onStatus: (String) -> Unit) : PurchasesUpdatedListener {
    companion object {
        const val MONTHLY_PRODUCT_ID = "storeflow_monthly"
        const val LIFETIME_PRODUCT_ID = "storeflow_lifetime_2590"
    }
    private val app = context.applicationContext
    private val scope = CoroutineScope(Dispatchers.IO)
    private var activity: Activity? = null
    private var products: Map<String, ProductDetails> = emptyMap()
    private val billing = BillingClient.newBuilder(app).setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection().build()

    fun connect(host: Activity, onProducts: (List<ProductDetails>) -> Unit) {
        activity = host
        billing.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    onStatus("เชื่อมต่อ Google Play ไม่สำเร็จ: " + result.debugMessage); return
                }
                val requests = listOf(
                    QueryProductDetailsParams.Product.newBuilder().setProductId(MONTHLY_PRODUCT_ID).setProductType(BillingClient.ProductType.SUBS).build(),
                    QueryProductDetailsParams.Product.newBuilder().setProductId(LIFETIME_PRODUCT_ID).setProductType(BillingClient.ProductType.INAPP).build()
                )
                billing.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(requests).build()) { response, resultData ->
                    if (response.responseCode == BillingClient.BillingResponseCode.OK) {
                        products = resultData.productDetailsList.associateBy { it.productId }
                        onProducts(resultData.productDetailsList)
                    } else onStatus("โหลดแพ็กเกจไม่สำเร็จ: " + response.debugMessage)
                }
                restorePurchases()
            }
            override fun onBillingServiceDisconnected() { onStatus("ขาดการเชื่อมต่อ Google Play") }
        })
    }

    fun buy(productId: String) {
        val host = activity ?: run { onStatus("ไม่พบหน้าจอสำหรับเปิด Google Play"); return }
        val product = products[productId] ?: run { onStatus("ไม่พบ Product ID ใน Play Console"); return }
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
        if (productId == MONTHLY_PRODUCT_ID) {
            val offer = product.subscriptionOfferDetails?.firstOrNull()?.offerToken
            if (offer.isNullOrBlank()) { onStatus("แพ็กเกจรายเดือนยังไม่มี Base plan / Offer"); return }
            productParams.setOfferToken(offer)
        }
        val flow = BillingFlowParams.newBuilder().setObfuscatedAccountId(organizationId.hashCode().toUInt().toString())
            .setProductDetailsParamsList(listOf(productParams.build())).build()
        val result = billing.launchBillingFlow(host, flow)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) onStatus("เปิดหน้าชำระเงินไม่สำเร็จ: " + result.debugMessage)
    }

    fun restorePurchases() {
        if (!billing.isReady) return
        listOf(BillingClient.ProductType.SUBS, BillingClient.ProductType.INAPP).forEach { type ->
            billing.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build()) { result, purchases ->
                if (result.responseCode == BillingClient.BillingResponseCode.OK) purchases
                    .filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }.forEach(::verifyOnServer)
            }
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> purchases.orEmpty().filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }.forEach(::verifyOnServer)
            BillingClient.BillingResponseCode.USER_CANCELED -> onStatus("ยกเลิกการซื้อ")
            else -> onStatus("การซื้อไม่สำเร็จ: " + result.debugMessage)
        }
    }

    private fun verifyOnServer(purchase: Purchase) {
        if (purchase.isAcknowledged && purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("organization_id", organizationId)
                    put("package_name", app.packageName)
                    put("purchase_token", purchase.purchaseToken)
                    put("order_id", purchase.orderId ?: "")
                    put("purchase_time", purchase.purchaseTime)
                    put("purchase_type", if (purchase.products.contains(MONTHLY_PRODUCT_ID)) "subscription" else "one_time")
                    put("product_ids", buildJsonArray { purchase.products.forEach { add(JsonPrimitive(it)) } })
                }
                val response = supabase.functions.invoke("storeflow-verify-play-purchase", body = payload)
                onStatus("ส่งตรวจสอบการซื้อกับ Google Play แล้ว: " + response.bodyAsText().take(120))
                if (!purchase.isAcknowledged) {
                    billing.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()) { ack ->
                        if (ack.responseCode != BillingClient.BillingResponseCode.OK) onStatus("ยืนยันการซื้อกับ Play ไม่สำเร็จ: " + ack.debugMessage)
                    }
                }
            } catch (e: Exception) { onStatus("ตรวจสอบการซื้อไม่สำเร็จ: " + (e.message ?: "เกิดข้อผิดพลาด")) }
        }
    }

    fun openSubscriptions() {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/account/subscriptions"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        app.startActivity(intent)
    }

    fun close() { if (billing.isReady) billing.endConnection(); activity = null }
}
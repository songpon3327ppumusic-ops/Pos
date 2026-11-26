package com.storeflow.app

import com.storeflow.app.data.StoreSubscription
import java.time.Instant
import java.time.OffsetDateTime

enum class StoreFeature {
    OVERVIEW, POS, PRODUCTS, BASIC_SALES_REPORTS, STAFF,
    SHIFTS, ATTENDANCE, STORE_PAYMENT_QR, BUSINESS_DOCUMENTS,
    PAYROLL_AUTO, TAX_DOCUMENTS, WITHHOLDING_DOCUMENTS, ADVANCED_DOCUMENTS,
    BARCODE_SCANNER, RECEIPT_PRINTER
}

enum class PlanTier(val value: String) {
    FREE("free"), BASIC("basic"), STANDARD("standard"), PREMIUM("premium"),
    LIFETIME("lifetime"), UNKNOWN("unknown");

    companion object {
        fun from(value: String?): PlanTier = entries.firstOrNull {
            it.value.equals(value?.trim(), ignoreCase = true)
        } ?: UNKNOWN
    }
}

enum class PlanStatus {
    ACTIVE, TRIAL, TRIALING, EXPIRED, PAST_DUE, CANCELED,
    CANCELLED, UNPAID, PAUSED, PENDING_PAYMENT, INCOMPLETE, FREE, UNKNOWN;

    companion object {
        fun from(value: String?): PlanStatus = entries.firstOrNull {
            it.name.equals(value?.trim(), ignoreCase = true)
        } ?: UNKNOWN
    }
}

/** Client-side feature visibility only. Supabase RLS, RPCs and SQL triggers remain authoritative. */
data class PlanPermissions(
    val planTier: PlanTier,
    val planStatus: PlanStatus,
    val expiresAt: Instant?,
    val userEmail: String?,
    val now: Instant = Instant.now()
) {
    companion object {
        const val SUPER_ADMIN_EMAIL = "songponsonma.3340@gmail.com"

        fun parseInstant(value: String?): Instant? = value?.let {
            runCatching { Instant.parse(it) }
                .recoverCatching { OffsetDateTime.parse(it).toInstant() }
                .getOrNull()
        }

        fun from(subscription: StoreSubscription?, userEmail: String?): PlanPermissions {
            val expiry = parseInstant(
                if (subscription?.status.equals("trial", true) ||
                    subscription?.status.equals("trialing", true)
                ) subscription?.trialEndsAt else subscription?.currentPeriodEnd
            )
            return PlanPermissions(
                planTier = PlanTier.from(subscription?.planTier ?: subscription?.planId),
                planStatus = PlanStatus.from(subscription?.status),
                expiresAt = expiry,
                userEmail = userEmail
            )
        }
    }

    val isSuperAdmin: Boolean
        get() = userEmail.equals(SUPER_ADMIN_EMAIL, ignoreCase = true)

    val isLifetime: Boolean
        get() = isSuperAdmin || planTier == PlanTier.LIFETIME

    val isTrialActive: Boolean
        get() = planStatus in setOf(PlanStatus.TRIAL, PlanStatus.TRIALING) &&
            expiresAt != null && expiresAt.isAfter(now)

    val isExpired: Boolean
        get() {
            if (isSuperAdmin || isLifetime || planStatus == PlanStatus.FREE) return false
            if (planStatus in setOf(
                    PlanStatus.EXPIRED, PlanStatus.PAST_DUE, PlanStatus.CANCELED,
                    PlanStatus.CANCELLED, PlanStatus.UNPAID, PlanStatus.PAUSED,
                    PlanStatus.PENDING_PAYMENT, PlanStatus.INCOMPLETE, PlanStatus.UNKNOWN
                )
            ) return true
            if (expiresAt != null && !expiresAt.isAfter(now)) return true
            if (planStatus in setOf(PlanStatus.TRIAL, PlanStatus.TRIALING)) return !isTrialActive
            return planStatus != PlanStatus.ACTIVE
        }

    val effectiveTier: PlanTier
        get() = when {
            isSuperAdmin || isLifetime -> PlanTier.LIFETIME
            isTrialActive -> PlanTier.STANDARD
            isExpired -> PlanTier.UNKNOWN
            planStatus == PlanStatus.FREE || planTier == PlanTier.FREE -> PlanTier.FREE
            planTier == PlanTier.PREMIUM -> PlanTier.PREMIUM
            planTier == PlanTier.STANDARD -> PlanTier.STANDARD
            planTier == PlanTier.BASIC -> PlanTier.BASIC
            else -> PlanTier.UNKNOWN
        }

    val hasFullAccess: Boolean
        get() = isSuperAdmin || isLifetime ||
            (!isExpired && effectiveTier == PlanTier.PREMIUM)

    val canCreateBill: Boolean
        get() = isSuperAdmin || isLifetime || !isExpired

    val statusLabel: String
        get() = when {
            isSuperAdmin || isLifetime -> "ใช้งานอยู่ • Lifetime"
            isTrialActive -> "ทดลองใช้ Standard"
            isExpired -> "หมดอายุ / รอชำระ"
            planStatus == PlanStatus.FREE || effectiveTier == PlanTier.FREE -> "ใช้งานฟรีตลอดชีพ"
            planStatus == PlanStatus.ACTIVE -> "ใช้งานอยู่"
            else -> "ยังไม่มีข้อมูลแพ็กเกจ"
        }

    val packageLabel: String
        get() = when (effectiveTier) {
            PlanTier.FREE -> "แพ็กเกจ: Free"
            PlanTier.BASIC -> "แพ็กเกจ: Basic"
            PlanTier.STANDARD -> "แพ็กเกจ: Standard"
            PlanTier.PREMIUM -> "แพ็กเกจ: Premium"
            PlanTier.LIFETIME -> "แพ็กเกจ: ซื้อขาดตลอดชีพ (Lifetime)"
            PlanTier.UNKNOWN -> if (isExpired) "แพ็กเกจหมดอายุ" else "ยังไม่มีแพ็กเกจ"
        }

    /** Expired subscriptions retain read-only access to existing records. */
    fun canReadFeature(feature: StoreFeature): Boolean = isExpired || hasFeature(feature)

    fun hasFeature(feature: StoreFeature): Boolean {
        if (isSuperAdmin || isLifetime || effectiveTier == PlanTier.PREMIUM) return true
        if (isExpired || effectiveTier == PlanTier.UNKNOWN) return false
        return when (feature) {
            StoreFeature.OVERVIEW, StoreFeature.POS, StoreFeature.PRODUCTS,
            StoreFeature.BASIC_SALES_REPORTS, StoreFeature.STORE_PAYMENT_QR,
            StoreFeature.BARCODE_SCANNER, StoreFeature.BUSINESS_DOCUMENTS -> true
            StoreFeature.STAFF -> effectiveTier in setOf(PlanTier.BASIC, PlanTier.STANDARD)
            StoreFeature.SHIFTS, StoreFeature.ATTENDANCE,
            StoreFeature.TAX_DOCUMENTS -> effectiveTier in setOf(PlanTier.STANDARD, PlanTier.PREMIUM, PlanTier.LIFETIME)
            StoreFeature.PAYROLL_AUTO, StoreFeature.WITHHOLDING_DOCUMENTS,
            StoreFeature.ADVANCED_DOCUMENTS, StoreFeature.RECEIPT_PRINTER -> false
        }
    }

    fun canCreateDocument(type: String): Boolean {
        if (isSuperAdmin || isLifetime || effectiveTier == PlanTier.PREMIUM) return true
        if (isExpired || effectiveTier == PlanTier.UNKNOWN) return false
        return when (effectiveTier) {
            PlanTier.FREE -> type == "receipt"
            PlanTier.BASIC -> type in setOf("receipt", "quotation", "delivery_note")
            PlanTier.STANDARD -> type in setOf(
                "receipt", "quotation", "delivery_note", "abbreviated_tax_invoice",
                "tax_invoice", "invoice", "billing_note"
            )
            else -> false
        }
    }

    fun productLimit(): Int? = when (effectiveTier) {
        PlanTier.FREE -> 20
        PlanTier.BASIC -> 50
        PlanTier.STANDARD, PlanTier.PREMIUM, PlanTier.LIFETIME -> null
        PlanTier.UNKNOWN -> 0
    }

    fun employeeLimit(): Int? = when (effectiveTier) {
        PlanTier.FREE -> 0
        PlanTier.BASIC -> 1
        PlanTier.STANDARD -> 5
        PlanTier.PREMIUM, PlanTier.LIFETIME -> null
        PlanTier.UNKNOWN -> 0
    }
}

@androidx.compose.runtime.Composable
fun StoreFlowUpgradeDialog(
    onDismiss: () -> Unit,
    onUpgrade: () -> Unit,
    message: String = "ฟีเจอร์นี้ต้องใช้แพ็กเกจที่สูงขึ้น หรือแพ็กเกจปัจจุบันหมดอายุ"
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { androidx.compose.material3.Text("อัปเกรดแพ็กเกจ StoreFlow") },
        text = { androidx.compose.material3.Text("$message\n\nเลือก Free / Basic / Standard / Premium / ซื้อขาด เพื่อเปิดใช้งาน") },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onUpgrade) {
                androidx.compose.material3.Text("ดูแพ็กเกจ")
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                androidx.compose.material3.Text("ภายหลัง")
            }
        }
    )
}

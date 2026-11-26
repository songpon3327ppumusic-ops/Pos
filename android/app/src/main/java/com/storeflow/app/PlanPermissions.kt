package com.storeflow.app

import com.storeflow.app.data.StoreSubscription
import java.time.Instant
import java.time.OffsetDateTime

enum class StoreFeature {
    OVERVIEW, POS, PRODUCTS, BASIC_SALES_REPORTS, STAFF,
    SHIFTS, ATTENDANCE, STORE_PAYMENT_QR, PAYROLL_AUTO,
    TAX_DOCUMENTS, BARCODE_SCANNER, RECEIPT_PRINTER
}

enum class PlanTier(val value: String) {
    BASIC("basic"), STANDARD("standard"), PREMIUM("premium"),
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

/** Client UX checks only. Supabase RLS, RPCs and SQL triggers are authoritative. */
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
            if (isSuperAdmin || isLifetime) return false
            if (planStatus in setOf(
                    PlanStatus.EXPIRED, PlanStatus.PAST_DUE, PlanStatus.CANCELED,
                    PlanStatus.CANCELLED, PlanStatus.UNPAID, PlanStatus.PAUSED,
                    PlanStatus.PENDING_PAYMENT, PlanStatus.INCOMPLETE, PlanStatus.UNKNOWN
                )
            ) return true
            if (expiresAt != null && !expiresAt.isAfter(now)) return true
            if (planStatus in setOf(PlanStatus.TRIAL, PlanStatus.TRIALING)) return !isTrialActive
            return planStatus !in setOf(PlanStatus.ACTIVE, PlanStatus.FREE)
        }

    val effectiveTier: PlanTier
        get() = when {
            isSuperAdmin || isLifetime -> PlanTier.LIFETIME
            isTrialActive -> PlanTier.STANDARD
            isExpired -> PlanTier.UNKNOWN
            planTier == PlanTier.PREMIUM -> PlanTier.PREMIUM
            planTier == PlanTier.STANDARD -> PlanTier.STANDARD
            planTier == PlanTier.BASIC || planStatus == PlanStatus.FREE -> PlanTier.BASIC
            else -> PlanTier.UNKNOWN
        }

    val hasFullAccess: Boolean
        get() = isSuperAdmin || isLifetime ||
            (!isExpired && effectiveTier == PlanTier.PREMIUM)

    val canCreateBill: Boolean
        get() = isSuperAdmin || isLifetime || !isExpired

    val packageLabel: String
        get() = when {
            isSuperAdmin || isLifetime -> "แพ็กเกจ: ซื้อขาดตลอดชีพ (Lifetime)"
            isTrialActive -> "แพ็กเกจ: ทดลองใช้ Standard (7 วัน)"
            isExpired -> "แพ็กเกจหมดอายุ"
            else -> "แพ็กเกจ: " + effectiveTier.name.lowercase()
                .replaceFirstChar { it.uppercase() }
        }

    fun hasFeature(feature: StoreFeature): Boolean {
        if (isSuperAdmin || isLifetime || effectiveTier == PlanTier.PREMIUM) return true
        if (isExpired || effectiveTier == PlanTier.UNKNOWN) return false
        return when (feature) {
            StoreFeature.OVERVIEW, StoreFeature.POS, StoreFeature.PRODUCTS,
            StoreFeature.BASIC_SALES_REPORTS, StoreFeature.STAFF -> true
            StoreFeature.SHIFTS, StoreFeature.ATTENDANCE,
            StoreFeature.STORE_PAYMENT_QR -> effectiveTier == PlanTier.STANDARD
            StoreFeature.PAYROLL_AUTO, StoreFeature.TAX_DOCUMENTS,
            StoreFeature.BARCODE_SCANNER, StoreFeature.RECEIPT_PRINTER -> false
        }
    }

    fun productLimit(): Int? = when (effectiveTier) {
        PlanTier.BASIC -> 50
        PlanTier.STANDARD, PlanTier.PREMIUM, PlanTier.LIFETIME -> null
        PlanTier.UNKNOWN -> 0
    }

    fun employeeLimit(): Int? = when (effectiveTier) {
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
        text = { androidx.compose.material3.Text("$message\n\nเลือก Basic / Standard / Premium / ซื้อขาด เพื่อเปิดใช้งาน") },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onUpgrade) {
                androidx.compose.material3.Text("อัปเกรดแพ็กเกจ")
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                androidx.compose.material3.Text("ภายหลัง")
            }
        }
    )
}

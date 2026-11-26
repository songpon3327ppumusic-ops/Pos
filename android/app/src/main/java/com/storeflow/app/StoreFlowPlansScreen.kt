package com.storeflow.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.storeflow.app.data.StoreFlowPlatformSettings
import com.storeflow.app.data.StoreFlowRepository
import com.storeflow.app.data.StoreSubscription
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

private data class StoreFlowPlan(
    val tier: String, val title: String, val monthly: Int, val yearly: Int,
    val products: String, val users: String, val features: String
)

private val storeFlowPlans = listOf(
    StoreFlowPlan("free", "Free", 0, 0, "สูงสุด 30 รายการ", "เจ้าของร้านเท่านั้น • พนักงาน 0 คน",
        "ภาพรวม • POS • รับเงินสด/QR ร้าน • สแกนบาร์โค้ด • รายงานรายวัน • ใบเสร็จรับเงินอย่างย่อ"),
    StoreFlowPlan("basic", "Basic", 149, 1490, "สูงสุด 150 รายการ", "พนักงานสูงสุด 2 คน",
        "ทุกอย่างใน Free • รายงานย้อนหลัง • ใบเสนอราคา • ใบส่งของ"),
    StoreFlowPlan("standard", "Standard", 299, 2990, "สินค้าไม่จำกัด", "พนักงานสูงสุด 6 คน",
        "ทุกอย่างใน Basic • ตารางกะงาน • ลงเวลา • ใบกำกับภาษีเต็มรูป"),
    StoreFlowPlan("premium", "Premium", 599, 5990, "สินค้าไม่จำกัด", "พนักงานไม่จำกัด",
        "ทุกฟีเจอร์ • เงินเดือนอัตโนมัติ • 50 ทวิ • รับ-ส่งของ • ใบสำคัญรับ-จ่าย"),
    StoreFlowPlan("lifetime", "ซื้อขาด (Lifetime)", 2590, 2590, "สินค้าไม่จำกัด", "พนักงานไม่จำกัด",
        "จ่ายครั้งเดียว ฿2,590 (ราคาปกติ ฿3,990) • ปลดล็อกทุกฟีเจอร์ตลอดชีพ")
)

// Subscription plans stay focused; payment collection is rendered in StoreFlowCheckoutSheet.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoreFlowPlansScreen(
    modifier: Modifier,
    organizationId: String,
    repository: StoreFlowRepository,
    currentSubscription: StoreSubscription?,
    permissions: PlanPermissions,
    onSubscriptionChanged: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var platformSettings by remember { mutableStateOf<StoreFlowPlatformSettings?>(null) }
    var platformQr by remember { mutableStateOf<Bitmap?>(null) }
    var platformAdmin by remember { mutableStateOf(false) }
    var selectedTier by remember(currentSubscription?.planTier, permissions.effectiveTier) {
        mutableStateOf(permissions.effectiveTier.value.takeIf { it != "unknown" } ?: "free")
    }
    var interval by remember { mutableStateOf("month") }
    var checkoutOpen by remember { mutableStateOf(false) }
    var slipPreview by remember { mutableStateOf<Bitmap?>(null) }
    var livePlans by remember { mutableStateOf<List<com.storeflow.app.data.StoreFlowSubscriptionPlan>>(emptyList()) }
    var adminPromptPayId by remember { mutableStateOf("") }
    var adminInstructions by remember { mutableStateOf("") }
    var billingEnabled by remember { mutableStateOf(false) }
    var slipBytes by remember { mutableStateOf<ByteArray?>(null) }
    var transactionRef by remember { mutableStateOf("") }
    var requests by remember { mutableStateOf(emptyList<com.storeflow.app.data.StoreFlowPlanPaymentRequest>()) }
    var adminRequests by remember { mutableStateOf(emptyList<com.storeflow.app.data.StoreFlowPlanPaymentRequest>()) }
    var adminSlipImages by remember { mutableStateOf<Map<String, Bitmap>>(emptyMap()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var adminAccountName by remember { mutableStateOf("") }
    var adminAccountNumber by remember { mutableStateOf("") }
    var adminBankName by remember { mutableStateOf("") }

    suspend fun reload() {
        livePlans = repository.subscriptionPlans()
        platformSettings = repository.platformSettings()
        platformSettings?.customQrUrl?.let { path ->
            platformQr = runCatching {
                val bytes = repository.downloadPlatformFile(path)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
        requests = repository.planPaymentRequests(organizationId)
        platformAdmin = permissions.isSuperAdmin || repository.isPlatformAdmin()
        adminRequests = if (platformAdmin) repository.allPendingPlanPaymentRequests() else emptyList()
        adminSlipImages = if (platformAdmin) adminRequests.mapNotNull { request ->
            val path = request.slipPath ?: return@mapNotNull null
            runCatching {
                val bytes = repository.downloadPlatformFile(path)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { request.id to it }
            }.getOrNull()
        }.toMap() else emptyMap()
        adminAccountName = platformSettings?.accountName.orEmpty()
        adminAccountNumber = platformSettings?.accountNumber.orEmpty()
        adminBankName = platformSettings?.bankName.orEmpty()
        adminPromptPayId = platformSettings?.promptpayId.orEmpty()
        adminInstructions = platformSettings?.instructions.orEmpty()
        billingEnabled = platformSettings?.isEnabled == true
    }

    LaunchedEffect(organizationId) {
        runCatching { reload() }.onFailure { error = it.message ?: "โหลดข้อมูลแพ็กเกจไม่สำเร็จ" }
    }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("อ่านรูปภาพไม่สำเร็จ")
                }
                require(bytes.size <= 6 * 1024 * 1024) { "รูปภาพต้องมีขนาดไม่เกิน 6 MB" }
                slipBytes = bytes
                slipPreview = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                message = "แนบสลิปแล้ว กรุณากรอกรหัสอ้างอิงจากสลิป"
            } catch (e: Exception) { error = e.message ?: "แนบสลิปไม่สำเร็จ" }
            finally { busy = false }
        }
    }

    val adminQrPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("อ่านรูป QR ไม่สำเร็จ")
                }
                val path = repository.uploadPlatformQr(bytes)
                val updated = (platformSettings ?: StoreFlowPlatformSettings()).copy(
                    customQrUrl = path,
                    accountName = adminAccountName,
                    accountNumber = adminAccountNumber,
                    bankName = adminBankName,
                    promptpayId = adminPromptPayId,
                    isEnabled = billingEnabled,
                    instructions = adminInstructions
                )
                repository.savePlatformSettings(updated)
                reload()
                message = "บันทึก QR รับเงินค่าแพ็กเกจ StoreFlow แล้ว"
            } catch (e: Exception) { error = e.message ?: "อัปโหลด QR ไม่สำเร็จ" }
            finally { busy = false }
        }
    }

    val selectedPlan = storeFlowPlans.firstOrNull { it.tier == selectedTier } ?: storeFlowPlans.first()
    val remotePlan = livePlans.firstOrNull { it.id == selectedTier && it.isActive }
    val amount = when (selectedTier) {
        "free" -> 0
        "lifetime" -> 2590
        else -> remotePlan?.let {
            (if (interval == "year") it.yearlyPriceThb else it.monthlyPriceThb).toInt()
        } ?: if (interval == "year") selectedPlan.yearly else selectedPlan.monthly
    }
    val currentTier = permissions.effectiveTier.value
    val statusLabel = permissions.statusLabel

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(vertical = 14.dp)
    ) {
        item {
            Text("แพ็กเกจ StoreFlow", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("เลือกแพ็กเกจที่เหมาะกับร้านค้า • ทดลองใช้ฟรี 7 วันสำหรับร้านใหม่",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = interval == "month", onClick = { interval = "month" }, label = { Text("รายเดือน") })
                    FilterChip(selected = interval == "year", onClick = { interval = "year" }, label = { Text("รายปี") })
                }
                if (interval == "year") Text("ประหยัดเมื่อเลือกรายปี", color = Color(0xFF15803D),
                    style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("แพ็กเกจปัจจุบันจากฐานข้อมูล", fontWeight = FontWeight.SemiBold)
                    Text(
                        if (permissions.isLifetime) "ซื้อขาดตลอดชีพ (Lifetime)" else currentTier.uppercase(),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Text("สถานะ: $statusLabel")
                    currentSubscription?.trialEndsAt?.let { Text("ทดลองใช้ถึง: " + formatStoreFlowThaiDateTime(it)) }
                    currentSubscription?.currentPeriodEnd?.let { Text("รอบบิลสิ้นสุด: " + formatStoreFlowThaiDateTime(it)) }
                }
            }
        }
        items(storeFlowPlans.size) { index ->
            val plan = storeFlowPlans[index]
            val isCurrent = currentTier == plan.tier || (permissions.isLifetime && plan.tier == "lifetime")
            Card(
                onClick = {
                    selectedTier = plan.tier
                    if (interval == "lifetime") interval = "month"
                    if (plan.tier != "free" && !isCurrent && !permissions.isLifetime) checkoutOpen = true
                },
                border = if (isCurrent || plan.tier == "standard") androidx.compose.foundation.BorderStroke(1.5.dp,
                    if (isCurrent) Color(0xFF059669) else MaterialTheme.colorScheme.primary) else null,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(plan.title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        when {
                            isCurrent -> Text("แพ็กเกจปัจจุบัน", color = Color(0xFF15803D), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                            plan.tier == "standard" -> Text("แนะนำ", color = Color(0xFFB45309), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                            plan.tier == "lifetime" -> Text("ซื้อขาด", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                    if (plan.tier == "free") {
                        Text("฿0 • ตลอดชีพ", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    } else if (plan.tier == "lifetime") {
                        Text("฿2,590 จ่ายครั้งเดียว", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "฿3,990",
                                style = MaterialTheme.typography.bodySmall.copy(
                                    textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("ประหยัด ฿1,400", color = Color(0xFF15803D), style = MaterialTheme.typography.labelSmall)
                        }
                    } else {
                        Text("฿" + amountForPlan(plan, livePlans, interval) + " / " +
                            if (interval == "year") "ปี" else "เดือน",
                            style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        if (interval == "year") Text("ประหยัดเมื่อชำระรายปี", color = Color(0xFF15803D),
                            style = MaterialTheme.typography.labelSmall)
                    }
                    Text("${plan.products} • ${plan.users}")
                    plan.features.split(" • ").filter { it.isNotBlank() }.forEach { feature ->
                        Row(verticalAlignment = Alignment.Top) {
                            Icon(Icons.Default.CheckCircle, null, tint = Color(0xFF16A34A), modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(7.dp))
                            Text(feature, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    Button(
                        onClick = {
                            selectedTier = plan.tier
                            if (plan.tier == "free") {
                                scope.launch {
                                    busy = true
                                    try {
                                        repository.selectFreePlan(organizationId)
                                        message = "เปลี่ยนเป็นแพ็กเกจ Free เรียบร้อย"
                                        onSubscriptionChanged()
                                        reload()
                                    } catch (e: Exception) { error = e.message ?: "เปลี่ยนแพ็กเกจ Free ไม่สำเร็จ" }
                                    finally { busy = false }
                                }
                            } else if (!isCurrent && !permissions.isLifetime) checkoutOpen = true
                        },
                        enabled = !busy && !isCurrent && !permissions.isLifetime,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(when {
                            isCurrent -> "กำลังใช้งานอยู่"
                            permissions.isLifetime -> "ได้รับสิทธิ์ Lifetime แล้ว"
                            plan.tier == "free" -> "ใช้แพ็กเกจ Free"
                            else -> "เลือก / อัปเกรดแพ็กเกจ"
                        })
                    }
                }
            }
        }
        if (requests.isNotEmpty()) item {
            Text("ประวัติคำขอชำระเงิน", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        items(requests.size) { index ->
            val request = requests[index]
            Card {
                Column(Modifier.padding(14.dp)) {
                    Text(request.planTier.uppercase() + " • ฿" + request.amountThb.toInt(), fontWeight = FontWeight.Bold)
                    Text("สถานะ: " + request.status)
                    Text("วันที่: " + formatStoreFlowThaiDateTime(request.createdAt), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        if (platformAdmin) item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("คำขอเปิดแพ็กเกจที่รออนุมัติ", fontWeight = FontWeight.Bold)
                    if (adminRequests.isEmpty()) Text("ไม่มีคำขอรอตรวจสอบ")
                    adminRequests.forEach { request ->
                        HorizontalDivider()
                        Text(request.planTier.uppercase() + " • ฿" + request.amountThb.toInt(),
                            fontWeight = FontWeight.SemiBold)
                        Text("ร้าน: " + request.organizationId.take(8) + "…")
                        Text("เลขอ้างอิง: " + (request.transactionRef?.takeIf { it.isNotBlank() } ?: "ไม่พบเลขอ้างอิง"))
                        adminSlipImages[request.id]?.let { slip ->
                            Image(slip.asImageBitmap(), contentDescription = "สลิปชำระแพ็กเกจ",
                                modifier = Modifier.fillMaxWidth().height(180.dp))
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(enabled = !busy, onClick = {
                                scope.launch {
                                    busy = true
                                    try {
                                        repository.reviewPlanPayment(request.id, true, "ตรวจสอบยอดโอนและอนุมัติโดยผู้ดูแล")
                                        reload()
                                        message = "อนุมัติแพ็กเกจให้ร้านเรียบร้อย"
                                    } catch (e: Exception) { error = e.message ?: "อนุมัติไม่สำเร็จ" }
                                    finally { busy = false }
                                }
                            }) { Text("อนุมัติ") }
                            OutlinedButton(enabled = !busy, onClick = {
                                scope.launch {
                                    busy = true
                                    try {
                                        repository.reviewPlanPayment(request.id, false, "สลิปหรือยอดชำระไม่ผ่านการตรวจสอบ")
                                        reload()
                                        message = "ปฏิเสธคำขอแล้ว"
                                    } catch (e: Exception) { error = e.message ?: "ปฏิเสธไม่สำเร็จ" }
                                    finally { busy = false }
                                }
                            }) { Text("ปฏิเสธ") }
                        }
                    }
                }
            }
        }
        if (platformAdmin) item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ตั้งค่าบัญชีรับเงินค่าแพ็กเกจ StoreFlow", fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("เปิดรับชำระเงินด้วยการโอน")
                        Switch(checked = billingEnabled, onCheckedChange = { billingEnabled = it }, enabled = !busy)
                    }
                    OutlinedTextField(adminAccountName, { adminAccountName = it }, label = { Text("ชื่อบัญชี") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(adminBankName, { adminBankName = it }, label = { Text("ธนาคาร") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(adminAccountNumber, { adminAccountNumber = it }, label = { Text("เลขบัญชี") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(adminPromptPayId, { adminPromptPayId = it }, label = { Text("เลขพร้อมเพย์ (ถ้ามี)") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(adminInstructions, { adminInstructions = it }, label = { Text("คำแนะนำการชำระเงิน") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
                    OutlinedButton(onClick = { adminQrPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("อัปโหลด / เปลี่ยน QR ของ StoreFlow") }
                    Button(onClick = {
                        scope.launch {
                            busy = true
                            try {
                                repository.savePlatformSettings((platformSettings ?: StoreFlowPlatformSettings()).copy(
                                    accountName = adminAccountName.trim().ifBlank { null },
                                    accountNumber = adminAccountNumber.trim().ifBlank { null },
                                    bankName = adminBankName.trim().ifBlank { null },
                                    promptpayId = adminPromptPayId.trim().ifBlank { null },
                                    isEnabled = billingEnabled,
                                    instructions = adminInstructions.trim().ifBlank { null }
                                ))
                                message = "บันทึกข้อมูลบัญชี StoreFlow แล้ว"
                                reload()
                            } catch (e: Exception) { error = e.message ?: "บันทึกไม่สำเร็จ" }
                            finally { busy = false }
                        }
                    }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("บันทึกข้อมูลบัญชี") }
                }
            }
        }
        error?.let { msg -> item { Text(msg, color = MaterialTheme.colorScheme.error) } }
        message?.let { msg -> item { Text(msg, color = MaterialTheme.colorScheme.primary) } }
    }

    if (checkoutOpen && selectedTier != "free") {
        StoreFlowCheckoutSheet(
            planName = selectedPlan.title,
            billingPeriod = if (selectedTier == "lifetime") "lifetime" else interval,
            amount = amount,
            settings = platformSettings,
            qrBitmap = platformQr,
            slipAttached = slipBytes != null,
            slipPreview = slipPreview,
            transactionRef = transactionRef,
            onTransactionRefChange = { transactionRef = it },
            busy = busy,
            error = error,
            manualPaymentAllowed = BuildConfig.ALLOW_MANUAL_SUBSCRIPTION_PAYMENT,
            onPickSlip = {
                imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
            onDismiss = {
                if (!busy) {
                    checkoutOpen = false
                    slipBytes = null
                    slipPreview = null
                    transactionRef = ""
                    error = null
                }
            },
            onSubmit = {
                scope.launch {
                    busy = true
                    error = null
                    try {
                        require(BuildConfig.ALLOW_MANUAL_SUBSCRIPTION_PAYMENT) {
                            "ช่องทางโอนเงินไม่เปิดใช้งานในแอป Google Play"
                        }
                        require(platformSettings?.isEnabled == true) {
                            "ผู้ดูแลยังไม่ได้เปิดรับชำระเงิน กรุณาติดต่อฝ่ายสนับสนุน"
                        }
                        require(slipBytes != null) { "กรุณาแนบรูปสลิปก่อนส่งคำขอ" }
                        require(transactionRef.trim().length >= 6) { "กรุณากรอกเลขอ้างอิงอย่างน้อย 6 ตัวอักษร" }
                        val requestId = UUID.randomUUID().toString()
                        val slipPath = repository.uploadPlanSlip(requestId, slipBytes!!)
                        repository.submitPlanPayment(
                            organizationId, selectedTier, if (selectedTier == "lifetime") "lifetime" else interval, amount.toDouble(),
                            slipPath, transactionRef.trim()
                        )
                        checkoutOpen = false
                        slipBytes = null
                        slipPreview = null
                        transactionRef = ""
                        requests = repository.planPaymentRequests(organizationId)
                        message = "ส่งหลักฐานชำระเงินแล้ว รอผู้ดูแลตรวจสอบและอนุมัติ"
                        onSubscriptionChanged()
                    } catch (e: Exception) {
                        error = e.message ?: "ส่งคำขอชำระเงินไม่สำเร็จ"
                    } finally {
                        busy = false
                    }
                }
            }
        )
    }
}


private fun amountForPlan(
    plan: StoreFlowPlan,
    plans: List<com.storeflow.app.data.StoreFlowSubscriptionPlan>,
    interval: String
): Int {
    val remote = plans.firstOrNull { it.id == plan.tier && it.isActive }
    return when {
        plan.tier == "free" -> 0
        plan.tier == "lifetime" -> 2590
        remote != null -> (if (interval == "year") remote.yearlyPriceThb else remote.monthlyPriceThb).toInt()
        interval == "year" -> plan.yearly
        else -> plan.monthly
    }
}


private fun formatStoreFlowThaiDateTime(value: String?): String {
    if (value.isNullOrBlank()) return "ไม่ระบุวันที่"
    return runCatching {
        val instant = runCatching { java.time.Instant.parse(value) }
            .getOrElse { java.time.OffsetDateTime.parse(value).toInstant() }
        java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy HH:mm", java.util.Locale("th", "TH"))
            .withZone(java.time.ZoneId.of("Asia/Bangkok"))
            .format(instant)
    }.getOrDefault(value)
}

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
    StoreFlowPlan("free", "Free", 0, 0, "สูงสุด 20 รายการ", "เจ้าของร้าน 1 คน",
        "POS • QR พร้อมเพย์/รูป QR ร้าน • สแกนบาร์โค้ด • รายงานยอดขายรายวัน • ใบเสร็จรับเงินอย่างย่อ"),
    StoreFlowPlan("basic", "Basic", 199, 1990, "สูงสุด 50 รายการ", "พนักงาน 1 คน",
        "ทุกอย่างใน Free • ใบเสนอราคา • ใบส่งของ"),
    StoreFlowPlan("standard", "Standard", 399, 3990, "สินค้าไม่จำกัด", "พนักงานสูงสุด 5 คน",
        "ทุกอย่างใน Basic • ตารางกะงาน • ลงเวลา • ใบกำกับภาษีเต็มรูป"),
    StoreFlowPlan("premium", "Premium", 799, 7990, "สินค้าไม่จำกัด", "พนักงานไม่จำกัด",
        "ทุกฟีเจอร์ • เงินเดือนอัตโนมัติ • 50 ทวิ • รับ-ส่งของ • ใบสำคัญรับ-จ่าย"),
    StoreFlowPlan("lifetime", "ซื้อขาด (Lifetime)", 2590, 2590, "สินค้าไม่จำกัด", "พนักงานไม่จำกัด",
        "จ่ายครั้งเดียว ฿2,590 (ราคาปกติ ฿3,990) • ปลดล็อกทุกฟีเจอร์ตลอดชีพ")
)

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
        platformSettings = repository.platformSettings()
        platformSettings?.customQrUrl?.let { path ->
            platformQr = runCatching {
                val bytes = repository.downloadPlatformFile(path)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
        requests = repository.planPaymentRequests(organizationId)
        platformAdmin = repository.isPlatformAdmin()
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
                    bankName = adminBankName
                )
                repository.savePlatformSettings(updated)
                reload()
                message = "บันทึก QR รับเงินค่าแพ็กเกจ StoreFlow แล้ว"
            } catch (e: Exception) { error = e.message ?: "อัปโหลด QR ไม่สำเร็จ" }
            finally { busy = false }
        }
    }

    val selectedPlan = storeFlowPlans.firstOrNull { it.tier == selectedTier } ?: storeFlowPlans.first()
    val amount = when (selectedTier) {
        "free" -> 0
        "lifetime" -> 2590
        else -> if (interval == "year") selectedPlan.yearly else selectedPlan.monthly
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
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("แพ็กเกจปัจจุบันจากฐานข้อมูล", fontWeight = FontWeight.SemiBold)
                    Text(currentTier.uppercase(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("สถานะ: $statusLabel")
                    currentSubscription?.trialEndsAt?.let { Text("ทดลองใช้ถึง: " + formatStoreFlowThaiDateTime(it)) }
                    currentSubscription?.currentPeriodEnd?.let { Text("รอบบิลสิ้นสุด: " + formatStoreFlowThaiDateTime(it)) }
                }
            }
        }
        items(storeFlowPlans.size) { index ->
            val plan = storeFlowPlans[index]
            val selected = selectedTier == plan.tier
            Card(
                onClick = {
                    selectedTier = plan.tier
                    if (plan.tier == "lifetime") interval = "lifetime"
                    else if (interval == "lifetime") interval = "month"
                },
                border = if (selected) androidx.compose.foundation.BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null,
                colors = CardDefaults.cardColors(containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(plan.title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        if (selected) Icon(Icons.Default.CheckCircle, "เลือกแล้ว", tint = MaterialTheme.colorScheme.primary)
                    }
                    if (plan.tier == "free") {
                        Text("฿0 • ตลอดชีพ", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    } else if (plan.tier == "lifetime") {
                        Text("฿2,590 จ่ายครั้งเดียว", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text("ราคาปกติ ฿3,990 • ประหยัด ฿1,400")
                    } else {
                        Text("฿${plan.monthly} / เดือน  •  ฿${plan.yearly} / ปี",
                            style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    }
                    Text("${plan.products} • ${plan.users}")
                    Text(plan.features, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        if (selectedTier !in setOf("lifetime", "free")) item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = interval == "month",
                    onClick = { interval = "month" },
                    label = { Text("รายเดือน") }
                )
                FilterChip(
                    selected = interval == "year",
                    onClick = { interval = "year" },
                    label = { Text("รายปี") }
                )
            }
        }
        if (selectedTier == "free") item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("เริ่มใช้งานแพ็กเกจ Free", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("ฟรีตลอดชีพ • สินค้า 20 รายการ • เจ้าของร้านใช้งานคนเดียว • QR รับเงินและ POS ใช้งานได้")
                    Button(
                        enabled = !busy && currentTier !in setOf("free", "lifetime"),
                        onClick = {
                            scope.launch {
                                busy = true; error = null; message = null
                                try {
                                    repository.selectFreePlan(organizationId)
                                    message = "เปลี่ยนเป็นแพ็กเกจ Free เรียบร้อย"
                                    onSubscriptionChanged()
                                } catch (e: Exception) {
                                    error = e.message ?: "เปลี่ยนแพ็กเกจ Free ไม่สำเร็จ"
                                } finally { busy = false }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(when {
                        busy -> "กำลังเปลี่ยนแพ็กเกจ..."
                        currentTier == "free" -> "ใช้งานแพ็กเกจนี้อยู่"
                        currentTier == "lifetime" -> "ร้านนี้ใช้สิทธิ์ Lifetime อยู่แล้ว"
                        else -> "ใช้แพ็กเกจ Free"
                    }) }
                }
            }
        }
        if (selectedTier != "free") item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ชำระค่าแพ็กเกจ StoreFlow", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("ยอดชำระ: ฿${amount}", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    if (platformQr != null) {
                        Image(platformQr!!.asImageBitmap(), contentDescription = "QR รับชำระค่าแพ็กเกจ StoreFlow",
                            modifier = Modifier.fillMaxWidth().height(220.dp))
                    } else {
                        Text("ยังไม่มี QR รับเงินค่าแพ็กเกจ กรุณาติดต่อผู้ดูแล StoreFlow")
                    }
                    platformSettings?.let { settings ->
                        Text("ชื่อบัญชี: ${settings.accountName ?: settings.promptpayName ?: "-"}")
                        Text("ธนาคาร: ${settings.bankName ?: "-"}")
                        Text("เลขบัญชี / พร้อมเพย์: ${settings.accountNumber ?: settings.promptpayId ?: "-"}")
                    }
                    OutlinedButton(onClick = { imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Default.CloudUpload, null); Spacer(Modifier.width(6.dp))
                        Text(if (slipBytes == null) "แนบรูปสลิปโอนเงิน" else "เปลี่ยนรูปสลิป")
                    }
                    OutlinedTextField(transactionRef, { transactionRef = it }, label = { Text("เลขอ้างอิงธุรกรรมจากสลิป") },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    Text("ระบบตรวจป้องกันเลขอ้างอิงซ้ำ และส่งให้ผู้ดูแล StoreFlow อนุมัติ ไม่เปิดสิทธิ์จากรูปสลิปโดยอัตโนมัติ",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(
                        onClick = {
                            scope.launch {
                                busy = true; error = null; message = null
                                try {
                                    require(platformQr != null) { "ผู้ดูแลยังไม่ได้ตั้งค่า QR รับเงินค่าแพ็กเกจ" }
                                    require(slipBytes != null) { "กรุณาแนบรูปสลิปก่อนส่งคำขอ" }
                                    require(transactionRef.trim().length >= 6) { "กรุณากรอกเลขอ้างอิงธุรกรรมให้ถูกต้อง" }
                                    val requestId = UUID.randomUUID().toString()
                                    val slipPath = repository.uploadPlanSlip(requestId, slipBytes!!)
                                    repository.submitPlanPayment(
                                        organizationId, selectedTier, interval, amount.toDouble(), slipPath, transactionRef.trim()
                                    )
                                    slipBytes = null; transactionRef = ""
                                    requests = repository.planPaymentRequests(organizationId)
                                    message = "ส่งหลักฐานชำระเงินแล้ว รอผู้ดูแลตรวจสอบและอนุมัติ"
                                    onSubscriptionChanged()
                                } catch (e: Exception) { error = e.message ?: "ส่งคำขอชำระเงินไม่สำเร็จ" }
                                finally { busy = false }
                            }
                        },
                        enabled = !busy && platformQr != null,
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(if (busy) "กำลังส่ง..." else "ส่งหลักฐานและขอเปิดใช้งานแพ็กเกจ") }
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
                        Text("เลขอ้างอิง: " + (request.transactionRef ?: "-"))
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
                    Text("ตั้งค่า QR รับเงินของ StoreFlow (ผู้ดูแลระบบ)", fontWeight = FontWeight.Bold)
                    OutlinedTextField(adminAccountName, { adminAccountName = it }, label = { Text("ชื่อบัญชี") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(adminBankName, { adminBankName = it }, label = { Text("ธนาคาร") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(adminAccountNumber, { adminAccountNumber = it }, label = { Text("เลขบัญชี / พร้อมเพย์") }, modifier = Modifier.fillMaxWidth())
                    OutlinedButton(onClick = { adminQrPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("อัปโหลด / เปลี่ยน QR ของ StoreFlow") }
                    Button(onClick = {
                        scope.launch {
                            busy = true
                            try {
                                repository.savePlatformSettings((platformSettings ?: StoreFlowPlatformSettings()).copy(
                                    accountName = adminAccountName, accountNumber = adminAccountNumber, bankName = adminBankName
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
}


private fun formatStoreFlowThaiDateTime(value: String?): String {
    if (value.isNullOrBlank()) return "-"
    return runCatching {
        val instant = runCatching { java.time.Instant.parse(value) }
            .getOrElse { java.time.OffsetDateTime.parse(value).toInstant() }
        java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy HH:mm", java.util.Locale("th", "TH"))
            .withZone(java.time.ZoneId.of("Asia/Bangkok"))
            .format(instant)
    }.getOrDefault(value)
}

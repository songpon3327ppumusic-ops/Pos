package com.storeflow.app

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.storeflow.app.data.StoreFlowPlatformSettings
import java.text.NumberFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoreFlowCheckoutSheet(
    planName: String,
    billingPeriod: String,
    amount: Int,
    settings: StoreFlowPlatformSettings?,
    qrBitmap: Bitmap?,
    slipAttached: Boolean,
    slipPreview: Bitmap?,
    transactionRef: String,
    onTransactionRefChange: (String) -> Unit,
    busy: Boolean,
    error: String?,
    manualPaymentAllowed: Boolean,
    onPickSlip: () -> Unit,
    onDismiss: () -> Unit,
    onSubmit: () -> Unit
) {
    val accountName = settings?.accountName?.takeIf { it.isNotBlank() }
    val accountNumber = settings?.accountNumber?.takeIf { it.isNotBlank() }
    val bankName = settings?.bankName?.takeIf { it.isNotBlank() }
    val promptPay = settings?.promptpayId?.takeIf { it.isNotBlank() }
    val hasPaymentDestination = qrBitmap != null || accountNumber != null || promptPay != null
    val settingsReady = settings?.isEnabled == true && accountName != null && hasPaymentDestination
    val money = NumberFormat.getNumberInstance(Locale("th", "TH"))

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                "ชำระค่าแพ็กเกจ",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Text(
                planName + " • " + when (billingPeriod) {
                    "lifetime" -> "ซื้อขาดตลอดชีพ"
                    "year" -> "รายปี"
                    else -> "รายเดือน"
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFFF0FDF4)),
                shape = RoundedCornerShape(16.dp)
            ) {
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    Text("ยอดชำระ", color = Color(0xFF166534))
                    Text(
                        "฿" + money.format(amount),
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF166534)
                    )
                }
            }

            if (!manualPaymentAllowed) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    )
                ) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text("ชำระผ่าน Google Play", fontWeight = FontWeight.Bold)
                        Text(
                            "บิลด์สำหรับ Google Play จะไม่แสดงช่องทางโอนเงินสำหรับซื้อสิทธิ์ดิจิทัล " +
                                "เพื่อให้เป็นไปตามข้อกำหนดการชำระเงินของ Google Play"
                        )
                    }
                }
            } else if (!settingsReady) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7ED))
                ) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            "ยังไม่พร้อมรับชำระเงิน",
                            color = Color(0xFF9A3412),
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            "ผู้ดูแล StoreFlow ยังไม่ได้เปิดรับชำระหรือกรอกข้อมูลบัญชีไม่ครบ " +
                                "กรุณาติดต่อฝ่ายสนับสนุน ระบบจะไม่แสดงข้อมูลบัญชีว่าง"
                        )
                    }
                }
            } else {
                Text("โอนเงินไปยังบัญชีนี้", fontWeight = FontWeight.Bold)
                if (qrBitmap != null) {
                    Image(
                        qrBitmap.asImageBitmap(),
                        contentDescription = "QR รับชำระค่าแพ็กเกจ StoreFlow",
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 260.dp)
                    )
                }
                CheckoutInfoRow("ชื่อบัญชี", accountName)
                CheckoutInfoRow("ธนาคาร", bankName)
                CheckoutInfoRow("เลขบัญชี", accountNumber)
                CheckoutInfoRow("พร้อมเพย์", promptPay)

                settings?.instructions?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall
                    )
                }

                HorizontalDivider()
                Text("หลักฐานการโอนเงิน", fontWeight = FontWeight.Bold)
                OutlinedButton(
                    onClick = onPickSlip,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (slipAttached) "เปลี่ยนรูปสลิป" else "แนบรูปสลิปโอนเงิน")
                }
                slipPreview?.let {
                    Image(
                        it.asImageBitmap(),
                        contentDescription = "ตัวอย่างสลิปที่แนบ",
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 220.dp)
                    )
                }
                OutlinedTextField(
                    value = transactionRef,
                    onValueChange = onTransactionRefChange,
                    label = { Text("เลขอ้างอิงธุรกรรม") },
                    supportingText = {
                        Text("กรอกเลขอ้างอิงจากสลิปอย่างน้อย 6 ตัวอักษร")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !busy
                )
                Text(
                    "ระบบจะป้องกันเลขอ้างอิงซ้ำ และส่งคำขอให้ผู้ดูแลตรวจสอบก่อนเปิดใช้งาน",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Button(
                    onClick = onSubmit,
                    enabled = !busy && settingsReady && slipAttached &&
                        transactionRef.trim().length >= 6,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(if (busy) "กำลังส่งหลักฐาน..." else "ส่งหลักฐานเพื่อขอเปิดใช้งาน")
                }
            }

            if (!error.isNullOrBlank()) {
                Text(
                    error,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            TextButton(
                onClick = onDismiss,
                enabled = !busy,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            ) {
                Text("ปิด")
            }
        }
    }
}

@Composable
private fun CheckoutInfoRow(label: String, value: String?) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            value?.takeIf { it.isNotBlank() } ?: "ยังไม่ได้ตั้งค่า",
            fontWeight = FontWeight.Medium
        )
    }
}

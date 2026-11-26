package com.storeflow.app

import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import androidx.core.content.FileProvider
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.storeflow.app.data.BusinessDocument
import com.storeflow.app.data.BusinessDocumentItem
import com.storeflow.app.data.DocumentLine
import com.storeflow.app.data.DocumentsRepository
import com.storeflow.app.data.StoreBusinessHeader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.time.LocalDate
import java.text.NumberFormat
import java.util.Locale

private val documentCurrency = NumberFormat.getCurrencyInstance(Locale("th", "TH"))
private fun documentTitle(type: String): String = when (type) {
    "quotation" -> "ใบเสนอราคา"; "invoice", "billing_note" -> "ใบแจ้งหนี้ / ใบวางบิล"
    "receipt" -> "ใบเสร็จรับเงินอย่างย่อ"; "tax_invoice" -> "ใบกำกับภาษีเต็มรูป"
    "abbreviated_tax_invoice" -> "ใบกำกับภาษีอย่างย่อ"; "delivery_note" -> "ใบส่งของ"
    "goods_receipt" -> "ใบรับสินค้า"; "withholding_certificate" -> "หนังสือรับรองหัก ณ ที่จ่าย (50 ทวิ)"
    "receipt_voucher" -> "ใบสำคัญรับเงิน"; "payment_voucher" -> "ใบสำคัญจ่าย"
    else -> type
}

@Composable
fun DocumentsScreen(
    modifier: Modifier,
    organizationId: String,
    repository: DocumentsRepository,
    readOnly: Boolean = false,
    permissions: PlanPermissions,
    onUpgrade: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var documents by remember { mutableStateOf(emptyList<BusinessDocument>()) }
    var selectedItems by remember { mutableStateOf(emptyList<BusinessDocumentItem>()) }
    var businessHeader by remember { mutableStateOf<StoreBusinessHeader?>(null) }
    var logoBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var loading by remember { mutableStateOf(true) }
    var creating by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<BusinessDocument?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    suspend fun refresh() {
        loading = true
        try {
            documents = withContext(Dispatchers.IO) { repository.list(organizationId) }
            businessHeader = withContext(Dispatchers.IO) { repository.businessHeader(organizationId) }
            logoBitmap = businessHeader?.logoPath?.let { path ->
                runCatching {
                    val bytes = withContext(Dispatchers.IO) { repository.downloadBusinessLogo(path) }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }.getOrNull()
            }
            error = null
        }
        catch (e: Exception) { error = e.message ?: "โหลดเอกสารไม่สำเร็จ" }
        finally { loading = false }
    }
    LaunchedEffect(organizationId) { refresh() }
    LaunchedEffect(selected?.id) {
        val doc = selected
        if (doc != null) {
            selectedItems = runCatching {
                withContext(Dispatchers.IO) { repository.items(organizationId, doc.id) }
            }.getOrDefault(emptyList())
        } else selectedItems = emptyList()
    }
    Column(modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("เอกสารร้านค้า", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("บันทึกเอกสารจริงในฐานข้อมูลร้านค้า", style = MaterialTheme.typography.bodySmall)
            }
            if (!readOnly) Button(onClick = { creating = true }) { Icon(Icons.Default.Add, null); Text("สร้าง") }
        }
        Spacer(Modifier.height(12.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (readOnly) Text("โหมดดูประวัติเท่านั้น • ต่ออายุแพ็กเกจเพื่อสร้างหรือแก้ไขเอกสาร", color = MaterialTheme.colorScheme.error)
        if (!loading && documents.isEmpty()) Text("ยังไม่มีเอกสาร", modifier = Modifier.padding(20.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(documents, key = { it.id }) { doc ->
                Card(Modifier.fillMaxWidth().clickable { selected = doc }) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(documentTitle(doc.documentType), fontWeight = FontWeight.SemiBold)
                            Text(doc.documentNo + " • " + (doc.partyName ?: "-"), style = MaterialTheme.typography.bodySmall)
                            Text(doc.issueDate + " • " + doc.status, style = MaterialTheme.typography.bodySmall)
                        }
                        Text(documentCurrency.format(doc.total), fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
    if (creating && !readOnly) DocumentForm(
        permissions = permissions,
        onUpgrade = onUpgrade,
        onDismiss = { creating = false },
        onSave = { type, party, taxId, address, due, description, qty, price, mode, notes, income, whRate ->
            scope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        val lines = listOf(DocumentLine(description, qty, unitPrice = price))
                        repository.create(organizationId, type, party, taxId, address, LocalDate.now().toString(), due, lines, mode, 7.0, notes, income, whRate)
                    }
                    creating = false; refresh()
                } catch (e: Exception) { error = e.message ?: "บันทึกเอกสารไม่สำเร็จ" }
            }
        }
    )
    selected?.let { doc ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(documentTitle(doc.documentType)) },
            text = { Text("เลขที่: " + doc.documentNo + "\nลูกค้า: " + (doc.partyName ?: "-") + "\nวันที่: " + doc.issueDate + "\nยอดรวม: " + documentCurrency.format(doc.total) + "\nสถานะ: " + doc.status) },
            confirmButton = {
                Row {
                    if (!readOnly && doc.documentType == "quotation") {
                        TextButton(onClick = {
                            scope.launch {
                                try {
                                    withContext(Dispatchers.IO) { repository.convertQuotation(organizationId, doc.id) }
                                    selected = null
                                    refresh()
                                } catch (e: Exception) { error = e.message ?: "แปลงใบเสนอราคาไม่สำเร็จ" }
                            }
                        }) { Text("แปลงเป็นใบแจ้งหนี้") }
                    }
                    TextButton(onClick = {
                        scope.launch {
                            try {
                                val file = withContext(Dispatchers.IO) { writeDocumentPdf(context, doc, businessHeader, logoBitmap, selectedItems) }
                                val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
                                val send = Intent(Intent.ACTION_SEND).apply { type = "application/pdf"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                                context.startActivity(Intent.createChooser(send, "แชร์ PDF / พิมพ์เอกสาร"))
                            } catch (e: Exception) { error = e.message ?: "สร้าง PDF ไม่สำเร็จ" }
                        }
                    }) { Icon(Icons.Default.PictureAsPdf, null); Text("PDF") }
                }
            },
            dismissButton = { TextButton(onClick = { selected = null }) { Text("ปิด") } }
        )
    }
}

@Composable
private fun DocumentForm(
    permissions: PlanPermissions,
    onUpgrade: () -> Unit,
    onDismiss: () -> Unit,
    onSave: (String,String,String,String,String?,String,Double,Double,String,String,String,Double) -> Unit
) {
    var type by remember { mutableStateOf(if (allowTaxDocuments) "tax_invoice" else "invoice") }
    var party by remember { mutableStateOf("") }; var taxId by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }; var due by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }; var qty by remember { mutableStateOf("1") }
    var price by remember { mutableStateOf("0") }; var mode by remember { mutableStateOf("exclude") }
    var notes by remember { mutableStateOf("") }; var income by remember { mutableStateOf("ค่าบริการ") }
    var whRate by remember { mutableStateOf("3") }; var error by remember { mutableStateOf<String?>(null) }
    val types = listOf(
        "abbreviated_tax_invoice", "tax_invoice", "withholding_certificate",
        "quotation", "invoice", "delivery_note", "goods_receipt",
        "receipt_voucher", "payment_voucher", "receipt"
    )
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text("สร้างเอกสาร") },
        text = {
            Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                types.forEach { t ->
                    val allowed = permissions.canCreateDocument(t)
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable {
                            if (allowed) type = t else onUpgrade()
                        },
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = type == t,
                            onClick = { if (allowed) type = t else onUpgrade() },
                            enabled = allowed
                        )
                        Text(
                            documentTitle(t),
                            modifier = Modifier.weight(1f),
                            color = if (allowed) MaterialTheme.colorScheme.onSurface
                                else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (!allowed) Icon(Icons.Default.Lock, contentDescription = "ต้องอัปเกรดแพ็กเกจ",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                OutlinedTextField(party, { party = it }, label = { Text("ชื่อลูกค้า / คู่ค้า") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(taxId, { taxId = it.filter(Char::isDigit).take(13) }, label = { Text("เลขผู้เสียภาษี 13 หลัก") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(address, { address = it }, label = { Text("ที่อยู่ลูกค้า") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(description, { description = it }, label = { Text("รายละเอียดรายการ") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(qty, { qty = it }, label = { Text("จำนวน") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(price, { price = it }, label = { Text("ราคาต่อหน่วย (บาท)") }, modifier = Modifier.fillMaxWidth())
                Text("VAT")
                listOf("exclude" to "แยก VAT 7%", "include" to "รวม VAT 7%", "non_vat" to "ไม่มี VAT").forEach { (v,l) ->
                    Row(verticalAlignment = Alignment.CenterVertically) { RadioButton(mode == v, onClick = { mode = v }); Text(l) }
                }
                OutlinedTextField(due, { due = it }, label = { Text("วันครบกำหนด YYYY-MM-DD (ถ้ามี)") }, modifier = Modifier.fillMaxWidth())
                if (type == "withholding_certificate") {
                    OutlinedTextField(income, { income = it }, label = { Text("ประเภทเงินได้") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(whRate, { whRate = it }, label = { Text("หัก ณ ที่จ่าย (%) เช่น 1, 3, 5") }, modifier = Modifier.fillMaxWidth())
                }
                OutlinedTextField(notes, { notes = it }, label = { Text("เงื่อนไข / หมายเหตุ") }, modifier = Modifier.fillMaxWidth())
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = {
            val q = qty.toDoubleOrNull(); val p = price.toDoubleOrNull(); val w = whRate.toDoubleOrNull() ?: 0.0
            if (!permissions.canCreateDocument(type)) error = "เอกสารนี้ต้องใช้แพ็กเกจที่สูงขึ้น"
            else if (party.isBlank() || q == null || p == null || q <= 0 || p < 0 || description.isBlank()) error = "กรุณาตรวจสอบชื่อ รายการ จำนวน และราคา"
            else if (taxId.isNotBlank() && taxId.length != 13) error = "เลขผู้เสียภาษีต้องมี 13 หลัก"
            else if (w !in 0.0..100.0) error = "อัตราหักภาษีไม่ถูกต้อง"
            else onSave(type, party, taxId, address, due.ifBlank { null }, description, q, p, mode, notes, income, w)
        }) { Text("บันทึกเอกสาร") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } }
    )
}

private fun writeDocumentPdf(context: Context, doc: BusinessDocument, header: StoreBusinessHeader?, logo: Bitmap?, items: List<BusinessDocumentItem>): File {
    val pdf = PdfDocument()
    val page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 14f }
    logo?.let { bitmap ->
        val target = Rect(42, 28, 112, 98)
        page.canvas.drawBitmap(bitmap, null, target, paint)
    }
    val storeName = header?.displayName?.takeIf { it.isNotBlank() }
        ?: header?.legalName?.takeIf { it.isNotBlank() } ?: "StoreFlow"
    val rows = listOf(
        storeName, header?.address?.takeIf { it.isNotBlank() } ?: "",
        "เลขผู้เสียภาษีร้าน: " + (header?.taxId ?: "-"),
        "สาขา: " + (header?.branchName ?: "สำนักงานใหญ่") + " (" + (header?.branchCode ?: "00000") + ")",
        documentTitle(doc.documentType), "เลขที่: " + doc.documentNo,
        "วันที่: " + doc.issueDate, "ลูกค้า/คู่ค้า: " + (doc.partyName ?: "-"),
        "เลขผู้เสียภาษีลูกค้า: " + (doc.partyTaxId ?: "-"),
        "รายการสินค้า/บริการ:",
        *items.mapIndexed { index, item -> (index + 1).toString() + ". " + item.description + " x " + item.quantity + " " + item.unit + " @ " + documentCurrency.format(item.unitPrice) + " = " + documentCurrency.format(item.lineTotal) }.toTypedArray(),
        "ยอดก่อนภาษี: " + documentCurrency.format(doc.subtotal),
        "ภาษี: " + documentCurrency.format(doc.taxAmount),
        "ยอดสุทธิ: " + documentCurrency.format(doc.total), "หมายเหตุ: " + (doc.notes ?: "-")
    )
    var y = if (logo == null) 60f else 112f
    rows.forEachIndexed { index, row ->
        paint.textSize = if (index < 2 || index == 8) 18f else 13f
        paint.isFakeBoldText = index < 2 || index == 8
        page.canvas.drawText(row.take(80), 42f, y, paint); y += 30f
    }
    pdf.finishPage(page)
    val out = File(context.cacheDir, "StoreFlow-" + doc.documentNo + ".pdf")
    FileOutputStream(out).use { pdf.writeTo(it) }; pdf.close()
    return out
}
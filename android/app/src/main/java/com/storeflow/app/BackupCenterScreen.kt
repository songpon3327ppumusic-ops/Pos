package com.storeflow.app

import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.storeflow.app.data.StoreFlowRepository
import com.storeflow.app.data.StoreOrganization
import kotlinx.coroutines.launch

@Composable
fun BackupCenterScreen(store: StoreOrganization, repo: StoreFlowRepository) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var backupJson by remember(store.id) { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var pendingRestore by remember { mutableStateOf<String?>(null) }
    var restoreMode by remember { mutableStateOf("merge") }
    var cloudItems by remember(store.id) { mutableStateOf(emptyList<com.storeflow.app.data.StoreBackup>()) }

    val saveJson = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) scope.launch {
            runCatching {
                val data = backupJson ?: error("กรุณาสร้างข้อมูลสำรองก่อน")
                context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray(Charsets.UTF_8)) }
                    ?: error("ไม่สามารถบันทึกไฟล์ได้")
                status = "บันทึกไฟล์ JSON สำเร็จ"
            }.onFailure { failure = it.message }
        }
    }
    val saveCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        if (uri != null) scope.launch {
            runCatching {
                val data = BackupManager.toCsv(backupJson ?: error("กรุณาสร้างข้อมูลสำรองก่อน"), store.id)
                context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray(Charsets.UTF_8)) }
                    ?: error("ไม่สามารถบันทึกไฟล์ได้")
                status = "บันทึกไฟล์ CSV สำเร็จ"
            }.onFailure { failure = it.message }
        }
    }
    val openJson = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            busy = true; failure = null
            try {
                val raw = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("อ่านไฟล์สำรองไม่ได้")
                require(raw.size <= 8 * 1024 * 1024) { "ไฟล์สำรองต้องมีขนาดไม่เกิน 8 MB" }
                val text = String(raw, Charsets.UTF_8)
                BackupManager.validate(text, store.id)
                pendingRestore = text
            } catch (e: Exception) { failure = e.message ?: "ไฟล์สำรองไม่ถูกต้อง" }
            finally { busy = false }
        }
    }

    LaunchedEffect(store.id) {
        runCatching { cloudItems = repo.listStoreBackups(store.id) }
        // Create at most one automatic snapshot per store per day while the owner is active.
        val prefs = context.getSharedPreferences("storeflow-auto-backup", Context.MODE_PRIVATE)
        val key = "last_auto_${store.id}"
        val last = prefs.getLong(key, 0L)
        if (System.currentTimeMillis() - last >= 24L * 60 * 60 * 1000) {
            runCatching {
                repo.createCloudSnapshot(store.id, "automatic")
                prefs.edit().putLong(key, System.currentTimeMillis()).apply()
                cloudItems = repo.listStoreBackups(store.id)
            }
        }
    }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Backup & Restore Center", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text("สำรองข้อมูลร้านนี้แยกตาม Store ID ครอบคลุมสินค้า สต็อก บิลขาย พนักงาน กะงาน และเอกสาร เก็บไฟล์ไว้ในที่ปลอดภัย")
            Button(enabled = !busy, onClick = {
                scope.launch {
                    busy = true; failure = null
                    try {
                        backupJson = repo.exportStoreBackup(store.id)
                        BackupManager.validate(backupJson!!, store.id)
                        status = "สร้างไฟล์สำรองล่าสุดแล้ว"
                    } catch (e: Exception) { failure = e.message ?: "สร้างข้อมูลสำรองไม่สำเร็จ" }
                    finally { busy = false }
                }
            }, modifier = Modifier.fillMaxWidth()) { Text(if (busy) "กำลังประมวลผล..." else "สร้างข้อมูลสำรอง") }
            OutlinedButton(enabled = !busy && backupJson != null, onClick = { saveJson.launch("StoreFlow-${store.id}-backup.json") }, modifier = Modifier.fillMaxWidth()) { Text("บันทึกลงเครื่อง (.json)") }
            OutlinedButton(enabled = !busy && backupJson != null, onClick = { saveCsv.launch("StoreFlow-${store.id}-export.csv") }, modifier = Modifier.fillMaxWidth()) { Text("ส่งออกเพื่อ Excel / Google Sheets (.csv)") }
            OutlinedButton(enabled = !busy && backupJson != null, onClick = {
                runCatching { BackupManager.shareBackup(context, backupJson!!, "StoreFlow-${store.id}-backup.json") }
                    .onFailure { failure = it.message }
            }, modifier = Modifier.fillMaxWidth()) { Text("แชร์ / ส่งไป Google Drive, LINE หรืออีเมล") }
            OutlinedButton(enabled = !busy, onClick = { openJson.launch(arrayOf("application/json", "text/json", "application/octet-stream")) }, modifier = Modifier.fillMaxWidth()) { Text("เลือกไฟล์ JSON เพื่อกู้คืน") }

            Divider()
            Text("Supabase Cloud Snapshots", fontWeight = FontWeight.SemiBold)
            OutlinedButton(enabled = !busy, onClick = {
                scope.launch {
                    busy = true; failure = null
                    try {
                        repo.createCloudSnapshot(store.id, "manual")
                        cloudItems = repo.listStoreBackups(store.id)
                        status = "สำรองขึ้น Supabase Cloud สำเร็จ"
                    } catch (e: Exception) { failure = e.message ?: "Cloud backup ไม่สำเร็จ" }
                    finally { busy = false }
                }
            }, modifier = Modifier.fillMaxWidth()) { Text("สำรองขึ้น Cloud ทันที") }
            if (cloudItems.isEmpty()) Text("ยังไม่มีจุดสำรองบน Cloud", style = MaterialTheme.typography.bodySmall)
            cloudItems.forEach { item ->
                Card {
                    Column(Modifier.fillMaxWidth().padding(12.dp)) {
                        Text(if (item.backupType == "automatic") "สำรองอัตโนมัติ" else "สำรองด้วยตนเอง", fontWeight = FontWeight.Medium)
                        Text(item.createdAt, style = MaterialTheme.typography.bodySmall)
                        Text("${item.fileSize / 1024} KB", style = MaterialTheme.typography.bodySmall)
                        TextButton(enabled = !busy, onClick = {
                            scope.launch {
                                busy = true; failure = null
                                try {
                                    pendingRestore = repo.downloadCloudSnapshot(item)
                                    BackupManager.validate(pendingRestore!!, store.id)
                                } catch (e: Exception) { failure = e.message ?: "ดาวน์โหลด snapshot ไม่สำเร็จ" }
                                finally { busy = false }
                            }
                        }) { Text("เลือกจุดนี้เพื่อกู้คืน") }
                    }
                }
            }
            status?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }

    if (pendingRestore != null) {
        AlertDialog(
            onDismissRequest = { pendingRestore = null },
            title = { Text("ยืนยันการกู้คืนข้อมูล") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ตรวจสอบไฟล์สำรองผ่านแล้ว เลือกรูปแบบการกู้คืน")
                    Row {
                        FilterChip(selected = restoreMode == "merge", onClick = { restoreMode = "merge" }, label = { Text("ผสานข้อมูลใหม่") })
                        Spacer(Modifier.width(8.dp))
                        FilterChip(selected = restoreMode == "replace", onClick = { restoreMode = "replace" }, label = { Text("เขียนทับข้อมูลเดิม") })
                    }
                    if (restoreMode == "replace") Text("คำเตือน: ข้อมูลปัจจุบันของร้านจะถูกลบก่อนนำเข้าข้อมูลสำรอง", color = MaterialTheme.colorScheme.error)
                }
            },
            confirmButton = {
                TextButton(enabled = !busy, onClick = {
                    val payload = pendingRestore ?: return@TextButton
                    scope.launch {
                        busy = true; failure = null
                        try {
                            status = repo.restoreStoreBackup(store.id, payload, restoreMode)
                            pendingRestore = null
                            status = "กู้คืนข้อมูลสำเร็จ: $status"
                        } catch (e: Exception) { failure = e.message ?: "กู้คืนข้อมูลไม่สำเร็จ" }
                        finally { busy = false }
                    }
                }) { Text("ยืนยันกู้คืน") }
            },
            dismissButton = { TextButton(onClick = { pendingRestore = null }) { Text("ยกเลิก") } }
        )
    }
}

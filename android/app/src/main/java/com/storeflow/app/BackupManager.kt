package com.storeflow.app

import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * StoreFlow portable backup utilities.
 * Backups are tenant-scoped exports produced by the authenticated Supabase RPC.
 */
object BackupManager {
    private const val APP_NAME = "StoreFlow"
    private const val SCHEMA_VERSION = 2
    private val parser = Json { ignoreUnknownKeys = false; isLenient = false }

    fun validate(jsonText: String, expectedStoreId: String): JsonObject {
        require(jsonText.toByteArray(Charsets.UTF_8).size <= 8 * 1024 * 1024) {
            "ไฟล์สำรองต้องมีขนาดไม่เกิน 8 MB"
        }
        val root = parser.parseToJsonElement(jsonText).jsonObject
        require(root["app"]?.jsonPrimitive?.content == APP_NAME) { "ไฟล์นี้ไม่ใช่ข้อมูลสำรอง StoreFlow" }
        require(root["schema_version"]?.jsonPrimitive?.content?.toIntOrNull() == SCHEMA_VERSION) {
            "ไม่รองรับเวอร์ชันไฟล์สำรองนี้"
        }
        require(root["organization_id"]?.jsonPrimitive?.content == expectedStoreId) {
            "ไฟล์สำรองนี้เป็นของร้านอื่น ไม่สามารถกู้คืนเข้าร้านนี้ได้"
        }
        val tables = root["tables"] as? JsonObject ?: error("ไม่พบข้อมูลตารางในไฟล์สำรอง")
        tables.forEach { (table, rows) ->
            require(table.matches(Regex("[a-z_]+"))) { "ชื่อตารางในไฟล์ไม่ถูกต้อง" }
            require(rows is JsonArray) { "ข้อมูลตาราง $table ไม่ถูกต้อง" }
            require(rows.size <= 20_000) { "จำนวนข้อมูลในตาราง $table มากเกินไป" }
        }
        return root
    }

    /** One CSV row per exported record; row_json preserves every original field for audit/export. */
    fun toCsv(jsonText: String, expectedStoreId: String): String {
        val root = validate(jsonText, expectedStoreId)
        val tables = root.getValue("tables").jsonObject
        val out = StringBuilder("\uFEFFtable_name,record_index,record_json\r\n")
        tables.forEach { (table, value) ->
            (value as JsonArray).forEachIndexed { index, record ->
                val compact = record.toString().replace("\r", " ").replace("\n", " ")
                out.append(csv(table)).append(',')
                    .append(index + 1).append(',')
                    .append(csv(compact)).append("\r\n")
            }
        }
        return out.toString()
    }

    private fun csv(value: String): String = "\"" + value.replace("\"", "\"\"") + "\""

    fun shareBackup(context: Context, jsonText: String, fileName: String) {
        val cacheFile = File(context.cacheDir, fileName)
        cacheFile.writeText(jsonText, Charsets.UTF_8)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", cacheFile)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "StoreFlow backup")
            clipData = ClipData.newUri(context.contentResolver, fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, "สำรองหรือแชร์ไฟล์ไปยัง Google Drive / แอปอื่น"))
    }
}

package com.storeflow.app

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

object PromptPayQr {
    fun payload(promptPayId: String, amount: Double): String {
        val id = promptPayId.filter(Char::isDigit)
        require(id.length == 10 || id.length == 13) {
            "กรุณาตั้งค่าเบอร์พร้อมเพย์ 10 หลัก หรือเลขบัตร 13 หลัก"
        }
        require(amount > 0.0)
        val normalizedId = if (id.length == 10) "0066" + id.drop(1) else id
        val merchantAccount = tlv("00", "A000000677010111") + tlv("01", normalizedId)
        val amountText = String.format(java.util.Locale.US, "%.2f", amount)
        val body = tlv("00", "01") +
            tlv("01", "12") +
            tlv("29", merchantAccount) +
            tlv("53", "764") +
            tlv("54", amountText) +
            tlv("58", "TH") +
            tlv("59", "STOREFLOW") +
            tlv("60", "BANGKOK") +
            "6304"
        return body + crc16(body).uppercase()
    }

    fun bitmap(payload: String, size: Int = 720): Bitmap {
        val matrix = MultiFormatWriter().encode(payload, BarcodeFormat.QR_CODE, size, size)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }

    private fun tlv(tag: String, value: String): String {
        require(value.length <= 99)
        return tag + value.length.toString().padStart(2, '0') + value
    }

    private fun crc16(input: String): String {
        var crc = 0xFFFF
        input.toByteArray(Charsets.UTF_8).forEach { byte ->
            crc = crc xor ((byte.toInt() and 0xFF) shl 8)
            repeat(8) {
                crc = if ((crc and 0x8000) != 0) ((crc shl 1) xor 0x1021) and 0xFFFF
                      else (crc shl 1) and 0xFFFF
            }
        }
        return crc.toString(16).padStart(4, '0')
    }
}

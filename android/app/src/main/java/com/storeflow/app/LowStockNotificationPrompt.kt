package com.storeflow.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

@Composable
fun LowStockNotificationPrompt(lowStockCount: Int) {
    val context = LocalContext.current
    var explain by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) postLowStockNotification(context, lowStockCount)
    }

    if (lowStockCount <= 0) return
    val permissionGranted = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    if (!permissionGranted) {
        Button(onClick = { explain = true }) { Text("เปิดการแจ้งเตือนสินค้าใกล้หมด") }
    } else {
        LaunchedEffect(lowStockCount) {
            val prefs = context.getSharedPreferences("storeflow-low-stock", Context.MODE_PRIVATE)
            val previous = prefs.getInt("last_notified_count", -1)
            if (previous != lowStockCount) {
                postLowStockNotification(context, lowStockCount)
                prefs.edit().putInt("last_notified_count", lowStockCount).apply()
            }
        }
    }

    if (explain) AlertDialog(
        onDismissRequest = { explain = false },
        title = { Text("อนุญาตการแจ้งเตือน") },
        text = { Text("StoreFlow จะแจ้งเตือนเมื่อมีสินค้าใกล้หมดสต็อก เพื่อช่วยให้ร้านเติมสินค้าได้ทันเวลา") },
        confirmButton = {
            TextButton(onClick = {
                explain = false
                if (Build.VERSION.SDK_INT >= 33) permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                else postLowStockNotification(context, lowStockCount)
            }) { Text("อนุญาต") }
        },
        dismissButton = { TextButton(onClick = { explain = false }) { Text("ภายหลัง") } }
    )
}

private fun postLowStockNotification(context: Context, count: Int) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val channelId = "storeflow_low_stock"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        manager.createNotificationChannel(
            NotificationChannel(channelId, "แจ้งเตือนสต็อกสินค้า", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }
    val notification = NotificationCompat.Builder(context, channelId)
        .setSmallIcon(android.R.drawable.stat_notify_error)
        .setContentTitle("StoreFlow: สินค้าใกล้หมด")
        .setContentText("มีสินค้าใกล้หมดสต็อก $count รายการ กรุณาตรวจสอบ")
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .setAutoCancel(true)
        .build()
    if (Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    ) NotificationManagerCompat.from(context).notify(4102, notification)
}

package com.storeflow.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

@Composable
fun BarcodeScanButton(onBarcode: (String) -> Unit) {
    val context = LocalContext.current
    val activity = context as? Activity
    var showRationale by remember { mutableStateOf(false) }
    var showScanner by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) showScanner = true
    }
    IconButton(onClick = {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        if (granted) showScanner = true
        else if (activity != null && ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.CAMERA)) showRationale = true
        else permissionLauncher.launch(Manifest.permission.CAMERA)
    }) { Icon(Icons.Default.QrCodeScanner, contentDescription = "สแกนบาร์โค้ด") }
    if (showRationale) AlertDialog(
        onDismissRequest = { showRationale = false },
        title = { Text("ต้องใช้กล้องเพื่อสแกนบาร์โค้ด") },
        text = { Text("StoreFlow ใช้กล้องเฉพาะเมื่อคุณกดสแกนสินค้า และไม่บันทึกภาพจากกล้อง") },
        confirmButton = { TextButton(onClick = { showRationale = false; permissionLauncher.launch(Manifest.permission.CAMERA) }) { Text("อนุญาต") } },
        dismissButton = { TextButton(onClick = { showRationale = false }) { Text("ยกเลิก") } }
    )
    if (showScanner) BarcodeScannerDialog(
        onDismiss = { showScanner = false },
        onResult = { value -> showScanner = false; onBarcode(value) }
    )
}

@Composable
private fun BarcodeScannerDialog(onDismiss: () -> Unit, onResult: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var scanError by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("สแกนบาร์โค้ดสินค้า") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AndroidView(
                    modifier = Modifier.fillMaxWidth().height(340.dp),
                    factory = { ctx ->
                        val previewView = PreviewView(ctx)
                        val providerFuture = ProcessCameraProvider.getInstance(ctx)
                        val executor = Executors.newSingleThreadExecutor()
                        val scanner = BarcodeScanning.getClient()
                        providerFuture.addListener({
                            try {
                                val provider = providerFuture.get()
                                val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                                val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                                analysis.setAnalyzer(executor) { proxy ->
                                    val media = proxy.image
                                    if (media == null) { proxy.close() } else {
                                        val image = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                                        scanner.process(image)
                                            .addOnSuccessListener { codes -> codes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue?.let(onResult) }
                                            .addOnFailureListener { scanError = it.message ?: "อ่านบาร์โค้ดไม่สำเร็จ" }
                                            .addOnCompleteListener { proxy.close() }
                                    }
                                }
                                provider.unbindAll()
                                provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
                            } catch (e: Exception) { scanError = e.message ?: "เปิดกล้องไม่สำเร็จ" }
                        }, ContextCompat.getMainExecutor(ctx))
                        previewView
                    }
                )
                scanError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Text("จัดบาร์โค้ดให้อยู่ในกรอบกล้อง", style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("ปิดกล้อง") } }
    )
}
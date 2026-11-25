package com.storeflow.app

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.storeflow.app.data.StoreFlowSupabase
import io.github.jan.supabase.auth.providers.Email
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Composable
fun AuthScreen(onAuthenticated: () -> Unit) {
    var isSignUp by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Text("StoreFlow", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(8.dp))
        Text(if (isSignUp) "สร้างบัญชีเจ้าของร้าน" else "เข้าสู่ระบบ",
            style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(20.dp))

        if (isSignUp) {
            OutlinedTextField(
                value = displayName, onValueChange = { displayName = it },
                label = { Text("ชื่อเจ้าของร้าน") }, singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(10.dp))
        }
        OutlinedTextField(
            value = email, onValueChange = { email = it.trim() },
            label = { Text("อีเมล") }, singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(
            value = password, onValueChange = { password = it },
            label = { Text("รหัสผ่าน") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(16.dp))

        Button(
            onClick = {
                if (email.isBlank() || password.length < 6 || (isSignUp && displayName.isBlank())) {
                    message = "กรอกข้อมูลให้ครบ และรหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร"
                    return@Button
                }
                scope.launch {
                    busy = true
                    message = null
                    try {
                        val client = StoreFlowSupabase.client
                        if (isSignUp) {
                            client.auth.signUpWith(Email) {
                                this.email = email
                                this.password = password
                                data = buildJsonObject { put("full_name", displayName) }
                            }
                            message = "สมัครบัญชีแล้ว หากระบบส่งอีเมลยืนยัน กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ"
                            isSignUp = false
                        } else {
                            client.auth.signInWith(Email) {
                                this.email = email
                                this.password = password
                            }
                            // The guarded database function assigns the first account as owner.
                            // It refuses to claim a store that already has another owner.
                            client.postgrest.rpc(
                                "bootstrap_store_owner",
                                buildJsonObject { put("p_org_slug", "storeflow") }
                            )
                            onAuthenticated()
                        }
                    } catch (error: Exception) {
                        message = error.message ?: "ดำเนินการไม่สำเร็จ กรุณาลองใหม่"
                    } finally {
                        busy = false
                    }
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth()
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            else Text(if (isSignUp) "สมัครบัญชีเจ้าของร้าน" else "เข้าสู่ระบบ")
        }
        TextButton(
            onClick = { isSignUp = !isSignUp; message = null },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (isSignUp) "มีบัญชีแล้ว? เข้าสู่ระบบ" else "ยังไม่มีบัญชี? สมัครเจ้าของร้าน")
        }
        message?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Modifier.height(12.dp))
        Text(
            "พนักงานต้องเข้าร่วมผ่านรหัสเชิญจากเจ้าของร้าน ระบบสมัครพนักงานจะเปิดใช้เมื่อเชื่อมขั้นตอนตรวจสอบรหัสเชิญกับฐานข้อมูล",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

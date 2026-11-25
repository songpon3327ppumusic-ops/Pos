package com.storeflow.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.storeflow.app.data.*
import com.storeflow.app.ui.theme.StoreFlowTheme
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.NumberFormat
import java.util.Locale
import java.time.LocalDate
import java.time.ZoneId

private val Page = Color(0xFFF6F8FB)
private val Green = Color(0xFF123C35)
private val Currency = NumberFormat.getCurrencyInstance(Locale("th", "TH"))

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        StoreFlowSupabase.client.handleDeeplinks(intent)
        setContent { StoreFlowTheme { StoreFlowRoot() } }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        StoreFlowSupabase.client.handleDeeplinks(intent)
    }
}

private data class Tab(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector)
private val tabs = listOf(
    Tab("ภาพรวม", Icons.Default.Storefront), Tab("ขาย", Icons.Default.PointOfSale),
    Tab("สินค้า", Icons.Default.Inventory2), Tab("รายงาน", Icons.Default.BarChart),
    Tab("ทีมงาน", Icons.Default.Groups), Tab("ตั้งค่า", Icons.Default.Settings)
)

@Composable
private fun StoreFlowRoot() {
    val client = remember { StoreFlowSupabase.client }
    var ready by remember { mutableStateOf(false) }
    var signedIn by remember { mutableStateOf(false) }
    LaunchedEffect(client) {
        signedIn = client.auth.currentSessionOrNull() != null
        ready = true
        client.auth.sessionStatus.collect { status ->
            when (status) {
                is SessionStatus.Authenticated -> { signedIn = true; ready = true }
                is SessionStatus.NotAuthenticated -> { signedIn = false; ready = true }
                else -> if (!ready && client.auth.currentSessionOrNull() == null) ready = true
            }
        }
    }
    when {
        !ready -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        !signedIn -> LoginScreen()
        else -> Workspace()
    }
}

@Composable
private fun LoginScreen() {
    val repo = remember { StoreFlowRepository(StoreFlowSupabase.client) }
    val scope = rememberCoroutineScope()
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Box(Modifier.fillMaxSize().padding(22.dp), contentAlignment = Alignment.Center) {
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(26.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(Modifier.padding(22.dp)) {
                Text("StoreFlow", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                Text("ระบบจัดการร้านค้า", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(24.dp))
                Text("เข้าสู่ระบบ", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                OutlinedButton(onClick = { scope.launch {
                    busy = true; error = null
                    try { repo.signInWithGoogle() } catch (e: Exception) { error = e.message ?: "Google Login ไม่สำเร็จ" }
                    finally { busy = false }
                } }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                    Icon(Icons.Default.AccountCircle, null); Spacer(Modifier.width(8.dp)); Text("เข้าสู่ระบบด้วย Google")
                }
                Spacer(Modifier.height(14.dp))
                OutlinedTextField(email, { email = it }, label = { Text("อีเมล") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(password, { password = it }, label = { Text("รหัสผ่าน") },
                    visualTransformation = PasswordVisualTransformation(), singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(14.dp))
                Button(onClick = { scope.launch {
                    busy = true; error = null
                    try { repo.signIn(email.trim(), password) }
                    catch (e: Exception) { error = e.message ?: "เข้าสู่ระบบไม่สำเร็จ" }
                    finally { busy = false }
                } }, enabled = !busy && email.isNotBlank() && password.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(50.dp)) {
                    Text(if (busy) "กำลังดำเนินการ..." else "เข้าสู่ระบบ")
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Text("บัญชีต้องได้รับคำเชิญหรืออนุมัติจากเจ้าของร้านก่อน",
                    color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Workspace() {
    val client = remember { StoreFlowSupabase.client }
    val repo = remember { StoreFlowRepository(client) }
    val scope = rememberCoroutineScope()
    var stores by remember { mutableStateOf(emptyList<Pair<StoreOrganization, String>>()) }
    var store by remember { mutableStateOf<StoreOrganization?>(null) }
    var role by remember { mutableStateOf("") }
    var products by remember { mutableStateOf(emptyList<StoreProduct>()) }
    var metrics by remember { mutableStateOf(StoreMetrics()) }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun loadStores() {
        loading = true
        try {
            stores = withContext(Dispatchers.IO) {
                repo.activeMemberships().mapNotNull { member ->
                    runCatching { repo.organization(member.organizationId) to member.role }.getOrNull()
                }
            }
            if (stores.size == 1) { store = stores.first().first; role = stores.first().second }
            error = null
        } catch (e: Exception) { error = e.message ?: "โหลดสิทธิ์ร้านค้าไม่สำเร็จ" }
        finally { loading = false }
    }
    suspend fun refresh() {
        val active = store ?: return
        busy = true
        try {
            val list = withContext(Dispatchers.IO) { repo.products(active.id) }
            metrics = withContext(Dispatchers.IO) { repo.metrics(active.id, list) }
            products = list
            error = null
        } catch (e: Exception) { error = e.message ?: "โหลดข้อมูลไม่สำเร็จ" }
        finally { busy = false }
    }
    LaunchedEffect(Unit) { loadStores() }
    LaunchedEffect(store?.id) { if (store != null) refresh() }

    if (loading) { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }; return }
    if (stores.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Storefront, null, tint = Green, modifier = Modifier.size(52.dp))
            Text("บัญชีนี้ยังไม่มีสิทธิ์เข้าถึงร้านค้า", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("ให้เจ้าของร้านส่งคำเชิญหรืออนุมัติบัญชีนี้", color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Button(onClick = { scope.launch { loadStores() } }) { Text("ตรวจสอบอีกครั้ง") }
            TextButton(onClick = { scope.launch { repo.signOut() } }) { Text("ออกจากระบบ") }
        }
        return
    }
    if (store == null) {
        Column(Modifier.fillMaxSize().padding(22.dp), verticalArrangement = Arrangement.Center) {
            Text("เลือกร้านค้า", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            stores.forEach { item ->
                Card(onClick = {
                    store = item.first; role = item.second
                }, modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Column(Modifier.padding(18.dp)) {
                        Text(item.first.name, fontWeight = FontWeight.Bold)
                        Text("สิทธิ์ " + item.second, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            TextButton(onClick = { scope.launch { repo.signOut() } }) { Text("ออกจากระบบ") }
        }
        return
    }
    val active = store!!
    Scaffold(
        containerColor = Page,
        topBar = {
            TopAppBar(
                title = { Column {
                    Text("StoreFlow", fontWeight = FontWeight.Bold)
                    Text(active.name, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                } },
                actions = { IconButton(onClick = { scope.launch { refresh() } }, enabled = !busy) {
                    if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Icon(Icons.Default.Refresh, "รีเฟรช")
                } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Page)
            )
        },
        bottomBar = {
            NavigationBar(containerColor = Color.White) {
                tabs.forEachIndexed { index, item ->
                    NavigationBarItem(selected = tab == index, onClick = { tab = index },
                        icon = { Icon(item.icon, item.label) }, label = { Text(item.label) })
                }
            }
        }
    ) { padding ->
        when (tab) {
            0 -> Dashboard(Modifier.padding(padding), active.name, metrics, error)
            1 -> PosScreen(Modifier.padding(padding), active.id, products, repo) { scope.launch { refresh() } }
            2 -> ProductsScreen(Modifier.padding(padding), active.id, products, repo,
                role in listOf("owner", "admin", "manager")) { scope.launch { refresh() } }
            3 -> ReportsScreen(Modifier.padding(padding), metrics, products)
            4 -> WorkforceScreen(Modifier.padding(padding), active.id, repo,
                role in listOf("owner", "admin", "hr"))
            else -> SettingsScreen(Modifier.padding(padding), active, role,
                client.auth.currentUserOrNull()?.email.orEmpty(),
                onSwitch = { store = null },
                onSignOut = { scope.launch { repo.signOut() } })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Dashboard(modifier: Modifier, storeName: String, metrics: StoreMetrics, error: String?) {
    LazyColumn(modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Text("ภาพรวมร้านค้า", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(storeName, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Card(shape = RoundedCornerShape(24.dp), colors = CardDefaults.cardColors(containerColor = Green)) {
                Column(Modifier.fillMaxWidth().padding(22.dp)) {
                    Text("ยอดขายวันนี้", color = Color(0xFFD1E9E2))
                    Text(money(metrics.todaySales), color = Color.White,
                        style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text("ข้อมูลจากรายการขายจริงใน Supabase", color = Color(0xFFD1E9E2))
                }
            }
        }
        item { Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Metric("บิลวันนี้", metrics.todayOrders.toString(), Modifier.weight(1f))
            Metric("สินค้าใกล้หมด", metrics.lowStockCount.toString(), Modifier.weight(1f))
        } }
        error?.let { msg -> item { Text(msg, color = MaterialTheme.colorScheme.error) } }
    }
}

@Composable
private fun Metric(title: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier, shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(Modifier.padding(16.dp)) {
            Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun ProductsScreen(
    modifier: Modifier, orgId: String, products: List<StoreProduct>,
    repo: StoreFlowRepository, canManage: Boolean, onChanged: () -> Unit
) {
    var adding by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<StoreProduct?>(null) }
    Column(modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("สินค้าและสต็อก", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(products.size.toString() + " รายการ", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (canManage) Button(onClick = { adding = true }) { Icon(Icons.Default.Add, null); Text("เพิ่ม") }
        }
        Spacer(Modifier.height(10.dp))
        if (products.isEmpty()) EmptyCard("ยังไม่มีสินค้า", "เพิ่มสินค้าเพื่อเริ่มขายและจัดการสต็อก")
        else LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(products, key = { it.id }) { p ->
                Card(onClick = { if (canManage) selected = p }, modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(p.name, fontWeight = FontWeight.SemiBold)
                            Text("SKU " + p.sku + " • " + money(p.price), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text("คงเหลือ " + qty(p.stock), fontWeight = FontWeight.Bold)
                            if (p.stock <= p.minStock) Text("ใกล้หมด", color = Color(0xFFB54708))
                        }
                    }
                }
            }
        }
    }
    if (adding) ProductDialog(onDismiss = { adding = false }, onSave = { sku, name, category, price, min ->
        repo.addProduct(orgId, sku, name, category, price, min)
        adding = false
        onChanged()
    })
    selected?.let { p -> StockDialog(p, onDismiss = { selected = null }, onSave = { delta, note ->
        repo.adjustStock(orgId, p.id, delta, note)
        selected = null
        onChanged()
    }) }
}

@Composable
private fun ProductDialog(onDismiss: () -> Unit, onSave: suspend (String, String, String, Double, Double) -> Unit) {
    val scope = rememberCoroutineScope()
    var sku by remember { mutableStateOf("") }; var name by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }; var price by remember { mutableStateOf("") }
    var minimum by remember { mutableStateOf("0") }; var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("เพิ่มสินค้า") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            OutlinedTextField(sku, { sku = it }, label = { Text("SKU") }, singleLine = true)
            OutlinedTextField(name, { name = it }, label = { Text("ชื่อสินค้า") }, singleLine = true)
            OutlinedTextField(category, { category = it }, label = { Text("หมวดหมู่") }, singleLine = true)
            OutlinedTextField(price, { price = it }, label = { Text("ราคาขาย") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            OutlinedTextField(minimum, { minimum = it }, label = { Text("แจ้งเตือนสต็อกต่ำกว่า") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } },
        confirmButton = { TextButton(enabled = !busy, onClick = {
            val p = price.toDoubleOrNull(); val m = minimum.toDoubleOrNull()
            if (sku.isBlank() || name.isBlank() || p == null || m == null || p < 0 || m < 0) error = "กรอกข้อมูลและตัวเลขให้ถูกต้อง"
            else scope.launch {
                busy = true
                try { onSave(sku, name, category, p, m) }
                catch (e: Exception) { error = e.message ?: "บันทึกไม่สำเร็จ" }
                finally { busy = false }
            }
        }) { Text(if (busy) "กำลังบันทึก" else "บันทึก") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } })
}

@Composable
private fun StockDialog(product: StoreProduct, onDismiss: () -> Unit, onSave: suspend (Double, String) -> Unit) {
    val scope = rememberCoroutineScope()
    var amount by remember { mutableStateOf("") }; var note by remember { mutableStateOf("ปรับสต็อก") }
    var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("ปรับสต็อก " + product.name) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("คงเหลือ " + qty(product.stock))
            OutlinedTextField(amount, { amount = it }, label = { Text("จำนวน (+ เพิ่ม / - ลด)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            OutlinedTextField(note, { note = it }, label = { Text("หมายเหตุ") })
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } },
        confirmButton = { TextButton(enabled = !busy, onClick = {
            val delta = amount.toDoubleOrNull()
            if (delta == null || delta == 0.0 || product.stock + delta < 0) error = "จำนวนไม่ถูกต้อง"
            else scope.launch {
                busy = true
                try { onSave(delta, note) } catch (e: Exception) { error = e.message ?: "ปรับสต็อกไม่สำเร็จ" }
                finally { busy = false }
            }
        }) { Text("ยืนยัน") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } })
}

@Composable
private fun PosScreen(
    modifier: Modifier, orgId: String, products: List<StoreProduct>,
    repo: StoreFlowRepository, onCompleted: () -> Unit
) {
    val cart = remember { mutableStateMapOf<String, Double>() }
    val scope = rememberCoroutineScope()
    var paying by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val selected = products.filter { (cart[it.id] ?: 0.0) > 0 }
    val total = selected.sumOf { it.price * (cart[it.id] ?: 0.0) }
    Column(modifier.fillMaxSize().padding(horizontal = 14.dp)) {
        Spacer(Modifier.height(8.dp))
        Text("ขายหน้าร้าน", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("เลือกสินค้าเพื่อเพิ่มลงตะกร้า", color = MaterialTheme.colorScheme.onSurfaceVariant)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            items(products, key = { it.id }) { p ->
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Row(Modifier.fillMaxWidth().padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(p.name, fontWeight = FontWeight.SemiBold)
                            Text(money(p.price) + " • คงเหลือ " + qty(p.stock), style = MaterialTheme.typography.bodySmall)
                        }
                        IconButton(enabled = p.stock > (cart[p.id] ?: 0.0), onClick = {
                            cart[p.id] = (cart[p.id] ?: 0.0) + 1
                        }) { Icon(Icons.Default.Add, "เพิ่ม") }
                        Text(qty(cart[p.id] ?: 0.0))
                        IconButton(enabled = (cart[p.id] ?: 0.0) > 0, onClick = {
                            val n = (cart[p.id] ?: 0.0) - 1
                            if (n <= 0) cart.remove(p.id) else cart[p.id] = n
                        }) { Icon(Icons.Default.Remove, "ลด") }
                    }
                }
            }
        }
        Card(Modifier.fillMaxWidth().padding(vertical = 8.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(selected.sumOf { cart[it.id] ?: 0.0 }.toInt().toString() + " ชิ้น", Modifier.weight(1f))
                    Text(money(total), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                Button(onClick = { paying = true }, enabled = selected.isNotEmpty() && !busy,
                    modifier = Modifier.fillMaxWidth()) { Text("ชำระเงินสด") }
                message?.let { Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
    if (paying) CashDialog(total, onDismiss = { paying = false }, onPay = { cash ->
        paying = false; busy = true
        scope.launch {
            try {
                val lines = selected.map { it to (cart[it.id] ?: 0.0) }
                val id = withContext(Dispatchers.IO) { repo.checkoutCash(orgId, lines, cash) }
                cart.clear()
                message = "บันทึกการขายสำเร็จ: " + id
                onCompleted()
            } catch (e: Exception) { message = e.message ?: "ชำระเงินไม่สำเร็จ" }
            finally { busy = false }
        }
    })
}

@Composable
private fun CashDialog(total: Double, onDismiss: () -> Unit, onPay: (Double) -> Unit) {
    var received by remember { mutableStateOf(String.format(Locale.US, "%.2f", total)) }
    var error by remember { mutableStateOf<String?>(null) }
    val cash = received.toDoubleOrNull()
    AlertDialog(onDismissRequest = onDismiss, title = { Text("รับชำระเงินสด") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("ยอดสุทธิ " + money(total), fontWeight = FontWeight.Bold)
            OutlinedTextField(received, { received = it }, label = { Text("รับเงินมา") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            if (cash != null) Text("เงินทอน " + money((cash-total).coerceAtLeast(0.0)))
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } },
        confirmButton = { TextButton(onClick = {
            if (cash == null || cash < total) error = "รับเงินไม่ครบยอด" else onPay(cash)
        }) { Text("ยืนยันการขาย") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } })
}


@Composable
private fun WorkforceScreen(
    modifier: Modifier,
    organizationId: String,
    repo: StoreFlowRepository,
    canManage: Boolean
) {
    val scope = rememberCoroutineScope()
    val today = remember { LocalDate.now(ZoneId.of("Asia/Bangkok")).toString() }
    var employees by remember { mutableStateOf(emptyList<StoreEmployee>()) }
    var shifts by remember { mutableStateOf(emptyList<StoreShift>()) }
    var attendance by remember { mutableStateOf(emptyList<AttendanceRecord>()) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var addingEmployee by remember { mutableStateOf(false) }
    var schedulingFor by remember { mutableStateOf<StoreEmployee?>(null) }

    suspend fun refresh() {
        busy = true
        error = null
        try {
            val data = withContext(Dispatchers.IO) {
                Triple(
                    repo.employees(organizationId),
                    repo.shifts(organizationId, today),
                    repo.attendanceToday(organizationId, today)
                )
            }
            employees = data.first
            shifts = data.second
            attendance = data.third
        } catch (e: Exception) {
            error = e.message ?: "โหลดข้อมูลบุคลากรไม่สำเร็จ"
        } finally {
            busy = false
            loading = false
        }
    }

    LaunchedEffect(organizationId) { refresh() }

    if (!canManage) {
        Column(modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Lock, null, modifier = Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("ไม่มีสิทธิ์จัดการบุคลากร", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("เมนูนี้สำหรับเจ้าของร้าน ผู้ดูแลระบบ และฝ่าย HR",
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    if (loading) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }

    Column(modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("พนักงานและกะงาน", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("วันนี้ $today • ${employees.size} คน", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = { scope.launch { refresh() } }, enabled = !busy) {
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                else Icon(Icons.Default.Refresh, "รีเฟรช")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { addingEmployee = true }, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.PersonAdd, null); Spacer(Modifier.width(5.dp)); Text("เพิ่มพนักงาน")
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Text("ตารางกะวันนี้", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            if (shifts.isEmpty()) item {
                EmptyCard("ยังไม่มีกะงานวันนี้", "เลือกพนักงานแล้วกดจัดกะเพื่อเพิ่มตารางเวลาทำงาน")
            }
            items(shifts, key = { it.id }) { shift ->
                val employee = employees.firstOrNull { it.id == shift.employeeId }
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Column(Modifier.fillMaxWidth().padding(14.dp)) {
                        Text(employee?.fullName ?: "พนักงาน", fontWeight = FontWeight.SemiBold)
                        Text(shift.shiftName, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("${shift.startsAt.take(16).replace("T", " ")} – ${shift.endsAt.take(16).replace("T", " ")}")
                        Text("พัก ${shift.breakMinutes} นาที", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item {
                Spacer(Modifier.height(4.dp))
                Text("พนักงาน", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            if (employees.isEmpty()) item { EmptyCard("ยังไม่มีพนักงาน", "เพิ่มข้อมูลพนักงานเพื่อจัดตารางกะงาน") }
            items(employees, key = { it.id }) { employee ->
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(employee.fullName, fontWeight = FontWeight.SemiBold)
                            Text("${employee.employeeCode} • ${employee.position ?: "พนักงาน"}",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall)
                        }
                        TextButton(onClick = { schedulingFor = employee }) { Text("จัดกะ") }
                    }
                }
            }
            item {
                Spacer(Modifier.height(4.dp))
                Text("บันทึกเวลาเข้างานวันนี้", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            if (attendance.isEmpty()) item { EmptyCard("ยังไม่มีรายการลงเวลา", "เมื่อพนักงานลงเวลา รายการจะแสดงที่นี่") }
            items(attendance, key = { it.id }) { record ->
                val employee = employees.firstOrNull { it.id == record.employeeId }
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Column(Modifier.padding(14.dp)) {
                        Text(employee?.fullName ?: "พนักงาน", fontWeight = FontWeight.SemiBold)
                        Text("เข้า: ${record.clockIn?.replace("T", " ")?.take(16) ?: "ยังไม่ลงเวลา"}")
                        Text("ออก: ${record.clockOut?.replace("T", " ")?.take(16) ?: "ยังไม่ออกกะ"}")
                        Text("ทำงาน ${record.workedMinutes} นาที • สาย ${record.lateMinutes} นาที",
                            color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }

    if (addingEmployee) EmployeeDialog(
        onDismiss = { addingEmployee = false },
        onSave = { name, position, department, type ->
            repo.addEmployee(organizationId, name, position, department, type)
            addingEmployee = false
            refresh()
        }
    )
    schedulingFor?.let { employee ->
        ScheduleShiftDialog(
            employee = employee,
            today = today,
            onDismiss = { schedulingFor = null },
            onSave = { date, start, end, name, breakMinutes ->
                repo.scheduleShift(organizationId, employee.id, date, start, end, name, breakMinutes)
                schedulingFor = null
                refresh()
            }
        )
    }
}

@Composable
private fun EmployeeDialog(
    onDismiss: () -> Unit,
    onSave: suspend (String, String, String, String) -> Unit
) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var position by remember { mutableStateOf("") }
    var department by remember { mutableStateOf("") }
    var type by remember { mutableStateOf("permanent") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("เพิ่มพนักงาน") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("ชื่อ-นามสกุล") }, singleLine = true)
                OutlinedTextField(position, { position = it }, label = { Text("ตำแหน่ง") }, singleLine = true)
                OutlinedTextField(department, { department = it }, label = { Text("แผนก") }, singleLine = true)
                Text("ประเภทการจ้าง")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("permanent" to "ประจำ", "part_time" to "พาร์ตไทม์", "daily" to "รายวัน").forEach { option ->
                        FilterChip(selected = type == option.first, onClick = { type = option.first }, label = { Text(option.second) })
                    }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(enabled = !busy, onClick = {
                if (name.isBlank()) error = "กรุณากรอกชื่อพนักงาน"
                else scope.launch {
                    busy = true
                    try { onSave(name, position, department, type) }
                    catch (e: Exception) { error = e.message ?: "เพิ่มพนักงานไม่สำเร็จ" }
                    finally { busy = false }
                }
            }) { Text(if (busy) "กำลังบันทึก..." else "บันทึก") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } }
    )
}

@Composable
private fun ScheduleShiftDialog(
    employee: StoreEmployee,
    today: String,
    onDismiss: () -> Unit,
    onSave: suspend (String, String, String, String, Int) -> Unit
) {
    val scope = rememberCoroutineScope()
    var date by remember { mutableStateOf(today) }
    var start by remember { mutableStateOf("09:00") }
    var end by remember { mutableStateOf("18:00") }
    var name by remember { mutableStateOf("กะกลางวัน") }
    var breakMinutes by remember { mutableStateOf("60") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("จัดกะให้ ${employee.fullName}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                OutlinedTextField(date, { date = it }, label = { Text("วันที่ (YYYY-MM-DD)") }, singleLine = true)
                OutlinedTextField(name, { name = it }, label = { Text("ชื่อกะ") }, singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(start, { start = it }, label = { Text("เริ่ม (HH:MM)") }, modifier = Modifier.weight(1f), singleLine = true)
                    OutlinedTextField(end, { end = it }, label = { Text("เลิก (HH:MM)") }, modifier = Modifier.weight(1f), singleLine = true)
                }
                OutlinedTextField(breakMinutes, { breakMinutes = it }, label = { Text("เวลาพัก (นาที)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(enabled = !busy, onClick = {
                val parsedBreak = breakMinutes.toIntOrNull()
                val validDate = runCatching { LocalDate.parse(date) }.isSuccess
                val validTime = Regex("^([01]\\d|2[0-3]):[0-5]\\d$").matches(start) &&
                    Regex("^([01]\\d|2[0-3]):[0-5]\\d$").matches(end)
                if (!validDate || !validTime || parsedBreak == null) error = "รูปแบบวันที่ เวลา หรือเวลาพักไม่ถูกต้อง"
                else scope.launch {
                    busy = true
                    try { onSave(date, start, end, name, parsedBreak) }
                    catch (e: Exception) { error = e.message ?: "สร้างกะงานไม่สำเร็จ" }
                    finally { busy = false }
                }
            }) { Text(if (busy) "กำลังบันทึก..." else "สร้างกะงาน") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } }
    )
}

@Composable
private fun ReportsScreen(modifier: Modifier, metrics: StoreMetrics, products: List<StoreProduct>) {
    LazyColumn(modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("รายงาน", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold) }
        item { Metric("ยอดขายวันนี้", money(metrics.todaySales), Modifier.fillMaxWidth()) }
        item { Metric("บิลวันนี้", metrics.todayOrders.toString(), Modifier.fillMaxWidth()) }
        item { Metric("สินค้าในระบบ", products.size.toString(), Modifier.fillMaxWidth()) }
        item { Metric("สินค้าใกล้หมด", metrics.lowStockCount.toString(), Modifier.fillMaxWidth()) }
    }
}

@Composable
private fun SettingsScreen(
    modifier: Modifier, store: StoreOrganization, role: String, email: String,
    onSwitch: () -> Unit, onSignOut: () -> Unit
) {
    Column(modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("ตั้งค่า", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("ร้านค้าที่ใช้งาน", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(store.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("สิทธิ์: " + role)
                Text(email, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        OutlinedButton(onClick = onSwitch, modifier = Modifier.fillMaxWidth()) { Text("เปลี่ยนร้านค้า") }
        Button(onClick = onSignOut, modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFB42318))) { Text("ออกจากระบบ") }
    }
}

@Composable
private fun EmptyCard(title: String, description: String) {
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(Modifier.padding(18.dp)) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(description, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun money(value: Double): String = Currency.format(value)
private fun qty(value: Double): String =
    if (value % 1.0 == 0.0) value.toLong().toString() else String.format(Locale.US, "%.3f", value)

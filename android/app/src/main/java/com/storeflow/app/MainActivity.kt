package com.storeflow.app

import android.content.Intent
import android.content.Context
import android.app.Activity
import android.print.PrintManager
import android.print.PrintAttributes
import android.webkit.WebView
import android.webkit.WebViewClient
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import com.storeflow.app.data.*
import com.storeflow.app.ui.theme.StoreFlowTheme
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.text.NumberFormat
import java.util.Locale
import java.time.LocalDate
import java.time.ZoneId
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import com.google.zxing.BinaryBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.EnumMap


private val ThaiDateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

private fun formatThaiDateTime(value: String?): String {
    if (value.isNullOrBlank()) return "-"
    val instant = runCatching { Instant.parse(value) }
        .recoverCatching { OffsetDateTime.parse(value).toInstant() }
        .getOrNull()
    return instant?.atZone(ZoneId.of("Asia/Bangkok"))?.format(ThaiDateTimeFormatter)
        ?: value.replace("T", " ").take(16)
}


private fun printStoreFlowReceipt(context: Context, receipt: String) {
    val activity = context as? Activity ?: return
    val webView = WebView(activity)
    webView.settings.javaScriptEnabled = false
    webView.webViewClient = object : WebViewClient() {
        override fun onPageFinished(view: WebView, url: String?) {
            val manager = activity.getSystemService(Context.PRINT_SERVICE) as PrintManager
            val adapter = view.createPrintDocumentAdapter("StoreFlow-Receipt")
            manager.print("StoreFlow ใบเสร็จ", adapter, PrintAttributes.Builder().build())
        }
    }
    val escaped = receipt.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace("\n", "<br>")
    webView.loadDataWithBaseURL(null,
        "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>" +
            "<body style='font-family:sans-serif;padding:20px;font-size:14px'>$escaped</body></html>",
        "text/HTML", "UTF-8", null)
}

private val Page = Color(0xFFF6F8FB)
private val Green = Color(0xFF123C35)
private val Currency = NumberFormat.getCurrencyInstance(Locale("th", "TH"))

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        StoreFlowSupabase.client.handleDeeplinks(intent)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, true)
        window.statusBarColor = android.graphics.Color.rgb(246, 248, 251)
        window.navigationBarColor = android.graphics.Color.WHITE
        androidx.core.view.WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
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
    Tab("สินค้า", Icons.Default.Inventory2), Tab("รายงาน", Icons.Default.BarChart)
)

@Composable
private fun StoreFlowRoot() {
    val context = LocalContext.current
    val client = remember { StoreFlowSupabase.client }
    var ready by remember { mutableStateOf(false) }
    var signedIn by remember { mutableStateOf(false) }
    LaunchedEffect(signedIn) {
        if (signedIn) {
            val prefs = context.getSharedPreferences("storeflow-consent", Context.MODE_PRIVATE)
            if (prefs.getBoolean("pending_google_consent", false)) {
                runCatching { StoreFlowRepository(client).recordPrivacyConsent() }
                prefs.edit().remove("pending_google_consent").apply()
            }
        }
    }
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
    val context = LocalContext.current
    val repo = remember { StoreFlowRepository(StoreFlowSupabase.client) }
    val scope = rememberCoroutineScope()
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var storeName by rememberSaveable { mutableStateOf("") }
    var inviteCode by rememberSaveable { mutableStateOf("") }
    var mode by rememberSaveable { mutableStateOf("login") }
    var pendingMode by rememberSaveable { mutableStateOf("") }
    var consentAccepted by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var info by remember { mutableStateOf<String?>(null) }

    fun runAuth(action: suspend () -> Unit) {
        scope.launch {
            busy = true; error = null; info = null
            try { action() }
            catch (e: Exception) { error = e.message ?: "ดำเนินการไม่สำเร็จ" }
            finally { busy = false }
        }
    }

    Box(Modifier.fillMaxSize().padding(22.dp), contentAlignment = Alignment.Center) {
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(26.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("StoreFlow", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                Text("ระบบจัดการร้านค้า", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    when(mode) {
                        "create" -> "สมัครเปิดร้านค้าใหม่"
                        "join" -> "เข้าร่วมร้านด้วยรหัสเชิญ"
                        else -> "เข้าสู่ระบบ"
                    },
                    style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold
                )
                if (mode == "login") {
                    OutlinedButton(onClick = {
                        context.getSharedPreferences("storeflow-consent", Context.MODE_PRIVATE)
                            .edit().putBoolean("pending_google_consent", true).apply()
                        runAuth { repo.signInWithGoogle() }
                    }, enabled = !busy && consentAccepted, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                        Icon(Icons.Default.AccountCircle, null); Spacer(Modifier.width(8.dp)); Text("เข้าสู่ระบบด้วย Google")
                    }
                }
                OutlinedTextField(email, { email = it }, label = { Text("อีเมล") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(password, { password = it }, label = { Text("รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)") },
                    visualTransformation = PasswordVisualTransformation(), singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                if (mode == "create") {
                    OutlinedTextField(storeName, { storeName = it }, label = { Text("ชื่อร้านค้า") },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    Text("ทดลองใช้ฟรี 7 วัน จากนั้นเลือกแพ็กเกจที่ต้องการ",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = consentAccepted, onCheckedChange = { consentAccepted = it })
                        Text("ฉันยินยอมให้ประมวลผลข้อมูลส่วนบุคคล และยอมรับข้อกำหนดการใช้งานกับนโยบายความเป็นส่วนตัว", style = MaterialTheme.typography.bodySmall)
                    }
                TextButton(onClick = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://benz-verse.com/storeflow-privacy")) ) } }) {
                    Text("อ่านนโยบายความเป็นส่วนตัว")
                }
                if (mode == "join") {
                    OutlinedTextField(inviteCode, { inviteCode = it.uppercase() },
                        label = { Text("รหัสเชิญจากเจ้าของร้าน") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth())
                }
                Button(
                    onClick = {
                        runAuth {
                            when(mode) {
                                "login" -> {
                                    repo.signIn(email.trim(), password)
                                    when (pendingMode) {
                                        "create" -> { repo.recordPrivacyConsent(); repo.createStore(storeName); pendingMode = "" }
                                        "join" -> { repo.recordPrivacyConsent(); repo.joinStore(inviteCode); pendingMode = "" }
                                    }
                                }
                                "create" -> {
                                    repo.signUp(email.trim(), password)
                                    if (StoreFlowSupabase.client.auth.currentSessionOrNull() != null) {
                                        repo.recordPrivacyConsent()
                                        repo.createStore(storeName)
                                    } else {
                                        pendingMode = "create"
                                        mode = "login"
                                        info = "สมัครบัญชีแล้ว กรุณายืนยันอีเมล จากนั้นเข้าสู่ระบบ ระบบจะสร้างร้านค้าให้ต่ออัตโนมัติ"
                                    }
                                }
                                "join" -> {
                                    repo.signUp(email.trim(), password)
                                    if (StoreFlowSupabase.client.auth.currentSessionOrNull() != null) {
                                        repo.recordPrivacyConsent()
                                        repo.joinStore(inviteCode)
                                    } else {
                                        pendingMode = "join"
                                        mode = "login"
                                        info = "สมัครบัญชีแล้ว กรุณายืนยันอีเมล จากนั้นเข้าสู่ระบบ ระบบจะเข้าร่วมร้านด้วยรหัสเชิญให้อัตโนมัติ"
                                    }
                                }
                            }
                        }
                    },
                    enabled = !busy && email.contains("@") && password.length >= 8 &&
                        (mode == "login" || (consentAccepted && mode == "create" && storeName.isNotBlank()) ||
                            (consentAccepted && mode == "join" && inviteCode.isNotBlank())),
                    modifier = Modifier.fillMaxWidth().height(50.dp)
                ) { Text(if (busy) "กำลังดำเนินการ..." else when(mode) {
                    "create" -> "สมัครและเปิดร้านค้า"
                    "join" -> "สมัครและเข้าร่วมร้าน"
                    else -> "เข้าสู่ระบบ"
                }) }
                if (mode != "login") {
                    TextButton(onClick = { mode = "login"; error = null; info = null },
                        modifier = Modifier.fillMaxWidth()) { Text("กลับไปเข้าสู่ระบบ") }
                } else {
                    TextButton(onClick = { mode = "create"; error = null; info = null },
                        modifier = Modifier.fillMaxWidth()) { Text("สมัครเปิดร้านค้าใหม่ (ทดลองใช้ฟรี 7 วัน)") }
                    TextButton(onClick = { mode = "join"; error = null; info = null },
                        modifier = Modifier.fillMaxWidth()) { Text("เข้าร่วมร้านด้วยรหัสเชิญ") }
                }
                info?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
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
    var subscription by remember { mutableStateOf<StoreSubscription?>(null) }
    var lastUpdated by remember { mutableStateOf("-") }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var extraScreen by rememberSaveable { mutableStateOf("") }
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showUpgradeDialog by remember { mutableStateOf(false) }

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
            subscription = withContext(Dispatchers.IO) { repo.subscription(active.id) }
            products = list
            lastUpdated = java.time.LocalDateTime.now(ZoneId.of("Asia/Bangkok")).format(DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm"))
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
    val signedInEmail = client.auth.currentUserOrNull()?.email.orEmpty()
    val permissions = remember(subscription, signedInEmail) {
        PlanPermissions.from(subscription, signedInEmail)
    }
    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            ModalDrawerSheet {
                Column(Modifier.fillMaxWidth().padding(18.dp)) {
                    Text("StoreFlow", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(active.name, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                HorizontalDivider()
                NavigationDrawerItem(
                    label = { Text("ทีมงาน / กะงาน / เงินเดือน") },
                    icon = { Icon(Icons.Default.Groups, null) },
                    selected = extraScreen == "workforce",
                    onClick = { extraScreen = "workforce"; scope.launch { drawerState.close() } }
                )
                NavigationDrawerItem(
                    label = { Text("เอกสาร") }, icon = { Icon(Icons.Default.Description, null) },
                    selected = extraScreen == "documents",
                    onClick = {
                        if (permissions.isExpired || permissions.hasFeature(StoreFeature.BUSINESS_DOCUMENTS) || permissions.hasFeature(StoreFeature.TAX_DOCUMENTS)) extraScreen = "documents"
                        else showUpgradeDialog = true
                        scope.launch { drawerState.close() }
                    }
                )
                NavigationDrawerItem(
                    label = { Text("ตั้งค่าร้านและ QR") }, icon = { Icon(Icons.Default.Settings, null) },
                    selected = extraScreen == "settings",
                    onClick = { extraScreen = "settings"; scope.launch { drawerState.close() } }
                )
                NavigationDrawerItem(
                    label = { Text("แพ็กเกจ Basic / Standard / Premium / ซื้อขาด") },
                    icon = { Icon(Icons.Default.WorkspacePremium, null) },
                    selected = extraScreen == "plans",
                    onClick = { extraScreen = "plans"; scope.launch { drawerState.close() } }
                )
                if (permissions.isSuperAdmin) NavigationDrawerItem(
                    label = { Text("จัดการอนุมัติแพ็กเกจลูกค้า (Super Admin)") },
                    icon = { Icon(Icons.Default.AdminPanelSettings, null) },
                    selected = extraScreen == "plans",
                    onClick = { extraScreen = "plans"; scope.launch { drawerState.close() } }
                )
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                NavigationDrawerItem(
                    label = { Text("ออกจากระบบ") }, icon = { Icon(Icons.Default.Logout, null) },
                    selected = false, onClick = { scope.launch { drawerState.close(); repo.signOut() } }
                )
            }
        }
    ) {
        Scaffold(
            containerColor = Page,
            topBar = {
                TopAppBar(
                    navigationIcon = {
                        IconButton(onClick = { scope.launch { drawerState.open() } }) {
                            Icon(Icons.Default.Menu, contentDescription = "เปิดเมนู")
                        }
                    },
                    title = { Column {
                        Text("StoreFlow", fontWeight = FontWeight.Bold)
                        if (!active.name.equals("StoreFlow", ignoreCase = true)) {
                            Text(active.name, style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
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
                        NavigationBarItem(selected = extraScreen.isEmpty() && tab == index,
                            onClick = { tab = index; extraScreen = "" },
                            icon = { Icon(item.icon, item.label) }, label = { Text(item.label) })
                    }
                }
            }
        ) { padding ->
            when (extraScreen) {
                "workforce" -> WorkforceScreen(Modifier.padding(padding), active.id, repo,
                    role in listOf("owner", "admin", "hr"), permissions,
                    onUpgrade = { extraScreen = "plans" })
                "documents" -> DocumentsScreen(Modifier.padding(padding), active.id, DocumentsRepository(client),
                    readOnly = permissions.isExpired,
                    allowTaxDocuments = permissions.hasFeature(StoreFeature.TAX_DOCUMENTS) || permissions.isExpired)
                "settings" -> SettingsScreen(Modifier.padding(padding), active, role,
                    client.auth.currentUserOrNull()?.email.orEmpty(), repo, permissions,
                    onUpgrade = { extraScreen = "plans" },
                    onSwitch = { store = null },
                    onSignOut = { scope.launch { repo.signOut() } })
                "plans" -> StoreFlowPlansScreen(Modifier.padding(padding), active.id, repo, subscription,
                    onSubscriptionChanged = { scope.launch { refresh() } })
                else -> when (tab) {
                    0 -> Dashboard(Modifier.padding(padding), active.name, metrics, error, lastUpdated)
                    1 -> PosScreen(Modifier.padding(padding), active.id, products, repo, role, permissions,
                        onUpgrade = { extraScreen = "plans" },
                        onOpenSettings = { extraScreen = "settings" }) { scope.launch { refresh() } }
                    2 -> ProductsScreen(Modifier.padding(padding), active.id, products, repo,
                        role in listOf("owner", "admin", "manager"), permissions,
                        onUpgrade = { extraScreen = "plans" }) { scope.launch { refresh() } }
                    else -> ReportsScreen(Modifier.padding(padding), metrics, products)
                }
            }
        }
        if (showUpgradeDialog) StoreFlowUpgradeDialog(
            onDismiss = { showUpgradeDialog = false },
            onUpgrade = { showUpgradeDialog = false; extraScreen = "plans" }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Dashboard(modifier: Modifier, storeName: String, metrics: StoreMetrics, error: String?, lastUpdated: String) {
    val context = LocalContext.current
    var online by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = manager.activeNetwork
            val caps = manager.getNetworkCapabilities(network)
            online = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            delay(5000)
        }
    }
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
                    Text((if (online) "ออนไลน์" else "ออฟไลน์") + " • อัปเดตล่าสุด " + lastUpdated, color = Color(0xFFD1E9E2))
                }
            }
        }
        item { Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Metric("บิลวันนี้", metrics.todayOrders.toString(), Modifier.weight(1f))
            Metric("สินค้าใกล้หมด", metrics.lowStockCount.toString(), Modifier.weight(1f))
        } }
        item { LowStockNotificationPrompt(metrics.lowStockCount) }
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
    repo: StoreFlowRepository, canManage: Boolean, permissions: PlanPermissions,
    onUpgrade: () -> Unit, onChanged: () -> Unit
) {
    var adding by remember { mutableStateOf(false) }
    var showUpgradeDialog by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<StoreProduct?>(null) }
    var editing by remember { mutableStateOf<StoreProduct?>(null) }
    var adjusting by remember { mutableStateOf<StoreProduct?>(null) }
    var deleting by remember { mutableStateOf<StoreProduct?>(null) }
    val scope = rememberCoroutineScope()
    Column(modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("สินค้าและสต็อก", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(products.size.toString() + " รายการ", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (canManage) Button(onClick = {
                val limit = permissions.productLimit()
                if (limit != null && products.size >= limit) showUpgradeDialog = true else adding = true
            }) { Icon(Icons.Default.Add, null); Text("เพิ่ม") }
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
    if (adding) ProductDialog(onDismiss = { adding = false }, onSave = { sku, name, category, price, min, initial, barcode ->
        repo.addProduct(orgId, sku, name, category, price, min, initial, barcode)
        adding = false
        onChanged()
    })
    selected?.let { p ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(p.name) },
            text = { Text("SKU " + p.sku + "\nคงเหลือ " + qty(p.stock) + "\nราคา " + money(p.price)) },
            confirmButton = {
                Column {
                    TextButton(onClick = { editing = p; selected = null }) { Text("แก้ไขสินค้า") }
                    TextButton(onClick = { adjusting = p; selected = null }) { Text("ปรับสต็อก") }
                    TextButton(onClick = { deleting = p; selected = null }) { Text("ลบสินค้า", color = MaterialTheme.colorScheme.error) }
                }
            },
            dismissButton = { TextButton(onClick = { selected = null }) { Text("ปิด") } }
        )
    }
    adjusting?.let { p -> StockDialog(p, onDismiss = { adjusting = null }, onSave = { delta, note ->
        repo.adjustStock(orgId, p.id, delta, note)
        adjusting = null
        onChanged()
    }) }
    editing?.let { p -> ProductEditDialog(
        product = p,
        onDismiss = { editing = null },
        onSave = { sku, name, category, price, minimum, barcode ->
            repo.updateProduct(orgId, p.id, sku, name, category, price, minimum, barcode)
            editing = null
            onChanged()
        }
    ) }
    if (showUpgradeDialog) StoreFlowUpgradeDialog(
        onDismiss = { showUpgradeDialog = false }, onUpgrade = onUpgrade,
        message = "ร้านนี้ถึงโควตาสินค้าหรือพนักงานของแพ็กเกจแล้ว"
    )
    deleting?.let { p ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("ยืนยันลบสินค้า") },
            text = { Text("สินค้า " + p.name + " จะถูกซ่อนจากรายการขาย ประวัติการขายเดิมยังคงอยู่") },
            confirmButton = { TextButton(onClick = {
                scope.launch {
                    try { repo.archiveProduct(orgId, p.id); deleting = null; onChanged() }
                    catch (e: Exception) { deleting = null }
                }
            }) { Text("ยืนยันลบ") } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("ยกเลิก") } }
        )
    }
}

@Composable
private fun ProductEditDialog(
    product: StoreProduct,
    onDismiss: () -> Unit,
    onSave: suspend (String, String, String, Double, Double, String) -> Unit
) {
    val scope = rememberCoroutineScope()
    var sku by remember { mutableStateOf(product.sku) }
    var name by remember { mutableStateOf(product.name) }
    var category by remember { mutableStateOf(product.category.orEmpty()) }
    var price by remember { mutableStateOf(product.price.toString()) }
    var minimum by remember { mutableStateOf(product.minStock.toString()) }
    var barcode by remember { mutableStateOf(product.barcode.orEmpty()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("แก้ไขสินค้า") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                OutlinedTextField(sku, { sku = it }, label = { Text("SKU") }, singleLine = true,
                    trailingIcon = { BarcodeScanButton(onBarcode = { barcode = it }) })
                OutlinedTextField(barcode, { barcode = it.filter(Char::isDigit) }, label = { Text("บาร์โค้ด") }, singleLine = true)
                OutlinedTextField(name, { name = it }, label = { Text("ชื่อสินค้า") }, singleLine = true)
                OutlinedTextField(category, { category = it }, label = { Text("หมวดหมู่") }, singleLine = true)
                OutlinedTextField(price, { price = it }, label = { Text("ราคาขาย") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                OutlinedTextField(minimum, { minimum = it }, label = { Text("แจ้งเตือนสต็อกต่ำกว่า") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                Text("สต็อกคงเหลือ: " + qty(product.stock) + " • ใช้เมนูปรับสต็อกเพื่อเปลี่ยนจำนวน")
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(enabled = !busy, onClick = {
            val p = price.toDoubleOrNull(); val m = minimum.toDoubleOrNull()
            if (sku.isBlank() || name.isBlank() || p == null || m == null || p < 0 || m < 0) error = "กรอกข้อมูลและตัวเลขให้ถูกต้อง"
            else scope.launch {
                busy = true
                try { onSave(sku, name, category, p, m, barcode) }
                catch (e: Exception) { error = e.message ?: "แก้ไขไม่สำเร็จ" }
                finally { busy = false }
            }
        }) { Text(if (busy) "กำลังบันทึก..." else "บันทึกการแก้ไข") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } }
    )
}

@Composable
private fun ProductDialog(onDismiss: () -> Unit, onSave: suspend (String, String, String, Double, Double, Double, String) -> Unit) {
    val scope = rememberCoroutineScope()
    var sku by remember { mutableStateOf("") }; var name by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }; var price by remember { mutableStateOf("") }
    var minimum by remember { mutableStateOf("0") }; var initial by remember { mutableStateOf("0") }
    var barcode by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("เพิ่มสินค้า") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            OutlinedTextField(sku, { sku = it }, label = { Text("SKU") }, singleLine = true, trailingIcon = { BarcodeScanButton(onBarcode = { barcode = it; if (sku.isBlank()) sku = it }) })
            OutlinedTextField(barcode, { barcode = it.filter(Char::isDigit) }, label = { Text("บาร์โค้ด") }, singleLine = true)
            OutlinedTextField(name, { name = it }, label = { Text("ชื่อสินค้า") }, singleLine = true)
            OutlinedTextField(category, { category = it }, label = { Text("หมวดหมู่") }, singleLine = true)
            OutlinedTextField(price, { price = it }, label = { Text("ราคาขาย") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            OutlinedTextField(initial, { initial = it }, label = { Text("จำนวนสต็อกตั้งต้น") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            OutlinedTextField(minimum, { minimum = it }, label = { Text("แจ้งเตือนสต็อกต่ำกว่า") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } },
        confirmButton = { TextButton(enabled = !busy, onClick = {
            val p = price.toDoubleOrNull(); val m = minimum.toDoubleOrNull(); val opening = initial.toDoubleOrNull()
            if (sku.isBlank() || name.isBlank() || p == null || m == null || opening == null || p < 0 || m < 0 || opening < 0) error = "กรอกข้อมูลและตัวเลขให้ถูกต้อง"
            else scope.launch {
                busy = true
                try { onSave(sku, name, category, p, m, opening, barcode) }
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
    repo: StoreFlowRepository, role: String, permissions: PlanPermissions,
    onUpgrade: () -> Unit, onOpenSettings: () -> Unit = {}, onCompleted: () -> Unit
) {
    val cart = remember { mutableStateMapOf<String, Double>() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var message by remember { mutableStateOf<String?>(null) }
    var receipt by remember { mutableStateOf<String?>(null) }
    val receiptSaveLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        if (uri != null) {
            val receiptText = receipt
            if (!receiptText.isNullOrBlank()) runCatching {
                val pdf = PdfDocument()
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { textSize = 14f }
                var y = 48f
                receiptText.lines().take(48).forEach { line ->
                    page.canvas.drawText(line.take(80), 40f, y, paint)
                    y += 20f
                }
                pdf.finishPage(page)
                context.contentResolver.openOutputStream(uri)?.use { pdf.writeTo(it) }
                    ?: error("บันทึกไฟล์ PDF ไม่สำเร็จ")
                pdf.close()
            }.onFailure { message = it.message ?: "บันทึก PDF ไม่สำเร็จ" }
        }
    }
    var search by rememberSaveable { mutableStateOf("") }
    var paymentDialog by remember { mutableStateOf(false) }
    var cashDialog by remember { mutableStateOf(false) }
    var promptPayDialog by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var showUpgradeDialog by remember { mutableStateOf(false) }
    var paymentSettings by remember(orgId) { mutableStateOf<StorePaymentSettings?>(null) }
    var customQrBitmap by remember(orgId) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(paymentSettings?.customQrUrl, paymentSettings?.qrImagePath) {
        val path = paymentSettings?.customQrUrl ?: paymentSettings?.qrImagePath
        customQrBitmap = if (path.isNullOrBlank()) null else runCatching {
            val bytes = withContext(Dispatchers.IO) { repo.downloadStoreQr(path) }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull()
    }
    val selected = products.filter { (cart[it.id] ?: 0.0) > 0 }
    val total = selected.sumOf { it.price * (cart[it.id] ?: 0.0) }
    val filtered = products.filter { p ->
        search.isBlank() || p.name.contains(search, true) ||
            p.sku.contains(search, true) || p.barcode.orEmpty().contains(search, true)
    }
    LaunchedEffect(orgId) {
        runCatching { paymentSettings = repo.storePaymentSettings(orgId) }
            .onFailure { message = it.message ?: "โหลดช่องทางชำระเงินไม่สำเร็จ" }
    }
    Column(modifier.fillMaxSize().padding(horizontal = 14.dp)) {
        Spacer(Modifier.height(8.dp))
        Text("ขายหน้าร้าน", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("ค้นหาชื่อสินค้า SKU หรือบาร์โค้ด", color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedTextField(
            value = search, onValueChange = { search = it },
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp),
            singleLine = true, label = { Text("ค้นหาสินค้า / สแกนบาร์โค้ด") },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = { Row(verticalAlignment = Alignment.CenterVertically) {
                if (permissions.hasFeature(StoreFeature.BARCODE_SCANNER)) BarcodeScanButton(onBarcode = { search = it })
                else IconButton(onClick = { showUpgradeDialog = true }) { Icon(Icons.Default.Lock, "สแกนบาร์โค้ดต้องอัปเกรด") }
                if (search.isNotBlank()) IconButton(onClick = { search = "" }) { Icon(Icons.Default.Close, "ล้าง") }
            } }
        )
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            if (filtered.isEmpty()) item { EmptyCard("ไม่พบสินค้า", "ตรวจสอบคำค้นหา SKU หรือบาร์โค้ด") }
            items(filtered, key = { it.id }) { p ->
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Row(Modifier.fillMaxWidth().padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(p.name, fontWeight = FontWeight.SemiBold)
                            Text(money(p.price) + " • คงเหลือ " + qty(p.stock),
                                style = MaterialTheme.typography.bodySmall)
                        }
                        IconButton(enabled = (cart[p.id] ?: 0.0) > 0, onClick = {
                            val n = (cart[p.id] ?: 0.0) - 1
                            if (n <= 0) cart.remove(p.id) else cart[p.id] = n
                        }) { Icon(Icons.Default.Remove, "ลดจำนวน") }
                        Text(qty(cart[p.id] ?: 0.0), modifier = Modifier.widthIn(min = 26.dp))
                        IconButton(enabled = p.stock > (cart[p.id] ?: 0.0), onClick = {
                            cart[p.id] = (cart[p.id] ?: 0.0) + 1
                        }) { Icon(Icons.Default.Add, "เพิ่มจำนวน") }
                    }
                }
            }
        }
        Card(Modifier.fillMaxWidth().padding(vertical = 8.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(selected.sumOf { cart[it.id] ?: 0.0 }.toInt().toString() + " ชิ้น",
                        Modifier.weight(1f))
                    Text(money(total), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { cart.clear() }, enabled = selected.isNotEmpty() && !busy) { Text("ล้างตะกร้า") }
                    Button(onClick = { paymentDialog = true }, enabled = selected.isNotEmpty() && !busy && permissions.canCreateBill,
                        modifier = Modifier.weight(1f)) {
                        Text(if (busy) "กำลังบันทึก..." else "เลือกวิธีชำระเงิน")
                    }
                }
                if (!permissions.canCreateBill) {
                    Text("แพ็กเกจหมดอายุ ไม่สามารถสร้างบิลใหม่ได้ แต่ยังดูข้อมูลเดิมและต่ออายุได้",
                        color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    TextButton(onClick = onUpgrade) { Text("ต่ออายุ / อัปเกรดแพ็กเกจ") }
                }
                message?.let { Text(it, color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
    if (paymentDialog) {
        AlertDialog(
            onDismissRequest = { paymentDialog = false },
            title = { Text("เลือกวิธีชำระเงิน") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (paymentSettings?.cashEnabled != false) Button(
                    onClick = { paymentDialog = false; cashDialog = true },
                    modifier = Modifier.fillMaxWidth()
                ) { Text("เงินสด") }
                if (paymentSettings?.promptpayEnabled == true && permissions.hasFeature(StoreFeature.STORE_PAYMENT_QR)) OutlinedButton(
                    onClick = {
                        if (paymentSettings?.promptpayId.isNullOrBlank()) {
                            message = "เจ้าของร้านยังไม่ได้ตั้งค่าเบอร์พร้อมเพย์"
                        } else {
                            paymentDialog = false; promptPayDialog = true
                        }
                    }, modifier = Modifier.fillMaxWidth()
                ) { Text("QR PromptPay / โอนเงิน") }
                if (paymentSettings?.cashEnabled == false && paymentSettings?.promptpayEnabled != true) {
                    Text("ร้านยังไม่ได้เปิดช่องทางรับชำระเงิน")
                }
            } },
            confirmButton = { TextButton(onClick = { paymentDialog = false }) { Text("ปิด") } }
        )
    }
    if (cashDialog) CashDialog(total, onDismiss = { cashDialog = false }, onPay = { cash ->
        cashDialog = false; busy = true
        scope.launch {
            try {
                val lines = selected.map { it to (cart[it.id] ?: 0.0) }
                val receiptLines = lines.joinToString("\n") { (p, q) -> "${p.name} x ${qty(q)} = ${money(p.price*q)}" }
                val id = withContext(Dispatchers.IO) {
                    repo.createPosSaleWithPayment(orgId, lines, "cash", cash)
                }
                cart.clear()
                receipt = "StoreFlow\nใบเสร็จรับเงิน\nเลขที่: $id\n\n$receiptLines\n\nยอดสุทธิ: ${money(total)}\nรับเงิน: ${money(cash)}\nเงินทอน: ${money(cash-total)}"
                message = "ชำระเงินสำเร็จ"
                onCompleted()
            } catch (e: Exception) { message = e.message ?: "ชำระเงินไม่สำเร็จ" }
            finally { busy = false }
        }
    })
    if (promptPayDialog) {
        PromptPayCheckoutDialog(
            organizationId = orgId,
            total = total,
            items = selected.map { it to (cart[it.id] ?: 0.0) },
            settings = paymentSettings,
            customQrBitmap = customQrBitmap,
            repo = repo,
            isOwner = role == "owner",
            onOpenSettings = onOpenSettings,
            onDismiss = { promptPayDialog = false },
            onPending = {
                cart.clear()
                promptPayDialog = false
                message = "ส่งสลิปแล้ว รอเจ้าของร้านตรวจสอบก่อนออกใบเสร็จ"
                onCompleted()
            },
            onPaid = { receiptText ->
                cart.clear()
                promptPayDialog = false
                receipt = receiptText
                message = "รับชำระเงินและตรวจสอบสลิปแล้ว"
                onCompleted()
            }
        )
    }
    if (showUpgradeDialog) StoreFlowUpgradeDialog(
        onDismiss = { showUpgradeDialog = false }, onUpgrade = { showUpgradeDialog = false; onUpgrade() }
    )
    receipt?.let { text ->
        AlertDialog(
            onDismissRequest = { receipt = null },
            title = { Text("ใบเสร็จรับเงิน") },
            text = { Text(text) },
            confirmButton = {
                Row {
                    TextButton(onClick = { receiptSaveLauncher.launch("StoreFlow-Receipt.pdf") }) { Text("บันทึก PDF") }
                    if (permissions.hasFeature(StoreFeature.RECEIPT_PRINTER)) TextButton(onClick = { printStoreFlowReceipt(context, text) }) { Text("พิมพ์") }
                    else TextButton(onClick = { showUpgradeDialog = true }) { Text("พิมพ์ 🔒") }
                    TextButton(onClick = {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text)
                        }
                        context.startActivity(Intent.createChooser(send, "แชร์ใบเสร็จ"))
                    }) { Text("แชร์ใบเสร็จ") }
                }
            },
            dismissButton = { TextButton(onClick = { receipt = null }) { Text("ปิด") } }
        )
    }
}

@Composable
private fun CashDialog(total: Double, onDismiss: () -> Unit, onPay: (Double) -> Unit) {
    var received by remember { mutableStateOf(total.toString()) }
    val amount = received.toDoubleOrNull() ?: 0.0
    val change = amount - total
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("รับชำระเงินสด") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("ยอดที่ต้องชำระ", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(money(total), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = received, onValueChange = { received = it.filter { ch -> ch.isDigit() || ch == '.' } },
                    label = { Text("จำนวนเงินที่รับมา") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth()
                )
                Text(if (change >= 0) "เงินทอน ${money(change)}" else "เงินขาด ${money(-change)}",
                    color = if (change >= 0) Color(0xFF027A48) else MaterialTheme.colorScheme.error,
                    fontWeight = FontWeight.SemiBold)
            }
        },
        confirmButton = {
            Button(onClick = { onPay(amount) }, enabled = amount >= total && amount > 0) {
                Text("ยืนยันรับเงิน")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } }
    )
}

@Composable
private fun PromptPayCheckoutDialog(
    organizationId: String,
    total: Double,
    items: List<Pair<StoreProduct, Double>>,
    settings: StorePaymentSettings?,
    customQrBitmap: Bitmap?,
    repo: StoreFlowRepository,
    isOwner: Boolean,
    onOpenSettings: () -> Unit,
    onDismiss: () -> Unit,
    onPending: () -> Unit,
    onPaid: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var slipBytes by remember { mutableStateOf<ByteArray?>(null) }
    var transactionRef by remember { mutableStateOf("") }
    var pendingSaleId by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val qrBitmap = remember(settings?.promptpayId, total) {
        runCatching { settings?.promptpayId?.let { PromptPayQr.bitmap(PromptPayQr.payload(it, total)) } }.getOrNull()
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri != null) {
            scope.launch {
                try {
                    val bytes = withContext(Dispatchers.IO) {
                        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                            ?: error("อ่านไฟล์สลิปไม่สำเร็จ")
                    }
                    require(bytes.size <= 6 * 1024 * 1024) { "ไฟล์สลิปต้องมีขนาดไม่เกิน 6 MB" }
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        ?: error("ไฟล์รูปภาพไม่ถูกต้อง")
                    val pixels = IntArray(bitmap.width * bitmap.height)
                    bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                    val hints = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java).apply {
                        put(DecodeHintType.TRY_HARDER, true)
                        put(DecodeHintType.POSSIBLE_FORMATS, listOf(BarcodeFormat.QR_CODE))
                    }
                    val decoded = MultiFormatReader().apply { setHints(hints) }
                        .decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(bitmap.width, bitmap.height, pixels))))
                    val ref = decoded.text.trim()
                    require(ref.isNotBlank()) { "ไม่พบ QR Code บนสลิป" }
                    slipBytes = bytes
                    transactionRef = ref.take(256)
                    error = null
                } catch (e: Exception) {
                    error = e.message ?: "อ่าน QR บนสลิปไม่สำเร็จ"
                }
            }
        }
    }
    AlertDialog(
        onDismissRequest = { if (pendingSaleId == null && !busy) onDismiss() },
        title = { Text("ชำระผ่าน QR PromptPay") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("ยอดที่ต้องโอน", style = MaterialTheme.typography.labelLarge)
                Text(money(total), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                if (customQrBitmap != null) {
                    Image(customQrBitmap.asImageBitmap(), contentDescription = "QR รับเงินของร้าน",
                        modifier = Modifier.fillMaxWidth().height(210.dp))
                } else {
                    OutlinedButton(onClick = onOpenSettings, modifier = Modifier.fillMaxWidth()) {
                        Text("ยังไม่มีรูป QR — ไปตั้งค่าแนบรูป QR ของร้านก่อน")
                    }
                }
                Text("ชื่อบัญชี: ${settings?.bankAccountName ?: settings?.promptpayName ?: "-"}")
                Text("ธนาคาร: ${settings?.bankName ?: "-"}")
                Text("เลขบัญชี / พร้อมเพย์: ${settings?.bankAccountNumber ?: settings?.promptpayId ?: "-"}")
                OutlinedButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !busy,
                    modifier = Modifier.fillMaxWidth()) { Text(if (slipBytes == null) "แนบรูปสลิปและอ่าน QR" else "เลือกสลิปใหม่") }
                if (transactionRef.isNotBlank()) {
                    Text("อ่านรหัสอ้างอิงจาก QR แล้ว", color = MaterialTheme.colorScheme.primary)
                    Text(transactionRef.take(90), style = MaterialTheme.typography.bodySmall, maxLines = 3)
                }
                if (isOwner && slipBytes != null) {
                    Text("กดยืนยันได้เมื่อเจ้าของร้านตรวจยอดและบัญชีผู้รับจากสลิปแล้วเท่านั้น",
                        style = MaterialTheme.typography.bodySmall)
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(enabled = customQrBitmap != null && slipBytes != null && transactionRef.isNotBlank() && !busy,
                onClick = {
                    val bytes = slipBytes ?: return@TextButton
                    scope.launch {
                        busy = true; error = null
                        try {
                            val saleId = pendingSaleId ?: withContext(Dispatchers.IO) {
                                repo.createPosSaleWithPayment(organizationId, items, "promptpay")
                            }.also { pendingSaleId = it }
                            val path = withContext(Dispatchers.IO) {
                                repo.uploadPosSlip(organizationId, saleId, bytes)
                            }
                            withContext(Dispatchers.IO) {
                                repo.attachPosSlip(organizationId, saleId, path, transactionRef)
                            }
                            if (isOwner) {
                                withContext(Dispatchers.IO) {
                                    repo.reviewPosSlip(organizationId, saleId, true, transactionRef,
                                        "เจ้าของร้านตรวจสอบยอดและผู้รับจากสลิปแล้ว")
                                }
                                val lines = items.joinToString("\n") { (p, q) -> "${p.name} x ${qty(q)} = ${money(p.price*q)}" }
                                onPaid("StoreFlow\nใบเสร็จรับเงิน\nเลขที่: $saleId\n\n$lines\n\nยอดสุทธิ: ${money(total)}\nชำระผ่าน: QR PromptPay\nสถานะ: เจ้าของร้านตรวจสอบแล้ว")
                            } else {
                                onPending()
                            }
                        } catch (e: Exception) {
                            error = e.message ?: "ส่งสลิปไม่สำเร็จ"
                        } finally { busy = false }
                    }
                }
            ) { Text(if (busy) "กำลังตรวจสอบและส่งสลิป..." else if (isOwner) "ยืนยันสลิปและออกใบเสร็จ" else "ส่งสลิปให้เจ้าของร้าน") }
        },
        dismissButton = {
            TextButton(enabled = !busy && pendingSaleId == null, onClick = onDismiss) { Text("ยกเลิก") }
        }
    )
}


@Composable
private fun WorkforceScreen(
    modifier: Modifier,
    organizationId: String,
    repo: StoreFlowRepository,
    canManage: Boolean,
    permissions: PlanPermissions,
    onUpgrade: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var showUpgradeDialog by remember { mutableStateOf(false) }
    val today = remember { LocalDate.now(ZoneId.of("Asia/Bangkok")).toString() }
    var employees by remember { mutableStateOf(emptyList<StoreEmployee>()) }
    var shifts by remember { mutableStateOf(emptyList<StoreShift>()) }
    var attendance by remember { mutableStateOf(emptyList<AttendanceRecord>()) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var addingEmployee by remember { mutableStateOf(false) }
    var schedulingFor by remember { mutableStateOf<StoreEmployee?>(null) }
    var salaryFor by remember { mutableStateOf<StoreEmployee?>(null) }

    suspend fun refresh() {
        busy = true
        error = null
        try {
            val data = withContext(Dispatchers.IO) {
                Triple(
                    repo.employees(organizationId),
                    if (permissions.canReadFeature(StoreFeature.SHIFTS)) repo.shifts(organizationId, today) else emptyList(),
                    if (permissions.canReadFeature(StoreFeature.ATTENDANCE)) repo.attendanceToday(organizationId, today) else emptyList()
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

    if (loading) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (!canManage) {
        if (!permissions.canReadFeature(StoreFeature.ATTENDANCE)) {
            Column(modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally) {
                Text("การลงเวลาเข้างาน", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("ฟีเจอร์นี้เปิดใช้งานตั้งแต่แพ็กเกจ Standard", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = { showUpgradeDialog = true }) { Text("อัปเกรดแพ็กเกจ") }
            }
            if (showUpgradeDialog) StoreFlowUpgradeDialog(
                onDismiss = { showUpgradeDialog = false }, onUpgrade = onUpgrade
            )
            return
        }
        SelfAttendanceScreen(
            modifier = modifier,
            employee = employees.firstOrNull(),
            shifts = shifts,
            attendance = attendance.firstOrNull(),
            onClockIn = { shiftId ->
                scope.launch {
                    busy = true
                    try {
                        withContext(Dispatchers.IO) { repo.clockIn(organizationId, shiftId) }
                        refresh()
                    } catch (e: Exception) { error = e.message ?: "ลงเวลาเข้างานไม่สำเร็จ" }
                    finally { busy = false }
                }
            },
            onClockOut = {
                scope.launch {
                    busy = true
                    try {
                        withContext(Dispatchers.IO) { repo.clockOut(organizationId) }
                        refresh()
                    } catch (e: Exception) { error = e.message ?: "ลงเวลาออกงานไม่สำเร็จ" }
                    finally { busy = false }
                }
            },
            busy = busy,
            error = error,
            canWriteAttendance = permissions.hasFeature(StoreFeature.ATTENDANCE)
        )
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
            Button(onClick = {
                val limit = permissions.employeeLimit()
                if (limit != null && employees.size >= limit) showUpgradeDialog = true
                else addingEmployee = true
            }, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.PersonAdd, null); Spacer(Modifier.width(5.dp))
                Text(if (permissions.employeeLimit() != null && employees.size >= permissions.employeeLimit()!!) "ถึงโควตาพนักงาน" else "เพิ่มพนักงาน")
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (permissions.canReadFeature(StoreFeature.SHIFTS)) item {
                Text("ตารางกะวันนี้", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            if (permissions.canReadFeature(StoreFeature.SHIFTS) && shifts.isEmpty()) item {
                EmptyCard("ยังไม่มีกะงานวันนี้", "เลือกพนักงานแล้วกดจัดกะเพื่อเพิ่มตารางเวลาทำงาน")
            }
            if (!permissions.canReadFeature(StoreFeature.SHIFTS)) item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                    Column(Modifier.fillMaxWidth().padding(14.dp)) {
                        Text("กะงานและลงเวลาเข้างาน", fontWeight = FontWeight.SemiBold)
                        Text("เปิดใช้งานได้ตั้งแต่แพ็กเกจ Standard", style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = { showUpgradeDialog = true }) { Text("อัปเกรดแพ็กเกจ") }
                    }
                }
            }
            if (permissions.canReadFeature(StoreFeature.SHIFTS)) items(shifts, key = { it.id }) { shift ->
                val employee = employees.firstOrNull { it.id == shift.employeeId }
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Column(Modifier.fillMaxWidth().padding(14.dp)) {
                        Text(employee?.fullName ?: "พนักงาน", fontWeight = FontWeight.SemiBold)
                        Text(shift.shiftName, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("${formatThaiDateTime(shift.startsAt)} – ${formatThaiDateTime(shift.endsAt)}")
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
                        if (canManage) {
                            TextButton(onClick = {
                                if (permissions.hasFeature(StoreFeature.PAYROLL_AUTO)) salaryFor = employee
                                else showUpgradeDialog = true
                            }) { Text(if (permissions.hasFeature(StoreFeature.PAYROLL_AUTO)) "เงินเดือน" else "เงินเดือน 🔒") }
                            if (permissions.hasFeature(StoreFeature.SHIFTS)) {
                                TextButton(onClick = { schedulingFor = employee }) { Text("จัดกะ") }
                            }
                        }
                    }
                }
            }
            if (permissions.canReadFeature(StoreFeature.ATTENDANCE)) item {
                Spacer(Modifier.height(4.dp))
                Text("บันทึกเวลาเข้างานวันนี้", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            if (permissions.canReadFeature(StoreFeature.ATTENDANCE) && attendance.isEmpty()) item { EmptyCard("ยังไม่มีรายการลงเวลา", "เมื่อพนักงานลงเวลา รายการจะแสดงที่นี่") }
            if (permissions.canReadFeature(StoreFeature.ATTENDANCE)) items(attendance, key = { it.id }) { record ->
                val employee = employees.firstOrNull { it.id == record.employeeId }
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Column(Modifier.padding(14.dp)) {
                        Text(employee?.fullName ?: "พนักงาน", fontWeight = FontWeight.SemiBold)
                        Text("เข้า: ${record.clockIn?.let { formatThaiDateTime(it) } ?: "ยังไม่ลงเวลา"}")
                        Text("ออก: ${record.clockOut?.let { formatThaiDateTime(it) } ?: "ยังไม่ออกกะ"}")
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
    salaryFor?.let { employee ->
        SalaryDialog(
            employee = employee,
            onDismiss = { salaryFor = null },
            onSave = { base, wage, ot, position, regular, social ->
                repo.updateEmployeeSalary(employee.id, base, wage, ot, position, regular, social)
                salaryFor = null
                refresh()
            }
        )
    }
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
    if (showUpgradeDialog) StoreFlowUpgradeDialog(
        onDismiss = { showUpgradeDialog = false }, onUpgrade = onUpgrade
    )
}


@Composable
private fun SelfAttendanceScreen(
    modifier: Modifier,
    employee: StoreEmployee?,
    shifts: List<StoreShift>,
    attendance: AttendanceRecord?,
    onClockIn: (String) -> Unit,
    onClockOut: () -> Unit,
    busy: Boolean,
    error: String?,
    canWriteAttendance: Boolean
) {
    val shift = employee?.let { person -> shifts.firstOrNull { it.employeeId == person.id } }
    Column(modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("ลงเวลาทำงาน", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (employee == null) {
            EmptyCard("ยังไม่พบโปรไฟล์พนักงาน", "ให้เจ้าของร้านหรือฝ่าย HR เชื่อมบัญชีนี้กับข้อมูลพนักงานก่อน")
        } else {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(employee.fullName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(employee.employeeCode, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(shift?.shiftName ?: "วันนี้ยังไม่มีกะงาน")
                    if (shift != null) {
                        Text("${formatThaiDateTime(shift.startsAt)} – ${formatThaiDateTime(shift.endsAt)}")
                    }
                    HorizontalDivider()
                    Text("เวลาเข้า: ${attendance?.clockIn?.let { formatThaiDateTime(it) } ?: "ยังไม่ลงเวลา"}")
                    Text("เวลาออก: ${attendance?.clockOut?.let { formatThaiDateTime(it) } ?: "ยังไม่ออกกะ"}")
                    if (attendance != null) {
                        Text("เวลาทำงาน ${attendance.workedMinutes} นาที • มาสาย ${attendance.lateMinutes} นาที",
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (attendance?.clockIn == null) {
                Button(
                    onClick = { shift?.let { onClockIn(it.id) } },
                    enabled = shift != null && !busy && canWriteAttendance,
                    modifier = Modifier.fillMaxWidth()
                ) { Text(if (busy) "กำลังบันทึก..." else "ลงเวลาเข้างาน") }
            } else if (attendance.clockOut == null) {
                Button(onClick = onClockOut, enabled = !busy && canWriteAttendance, modifier = Modifier.fillMaxWidth()) {
                    Text(if (busy) "กำลังบันทึก..." else "ลงเวลาออกงาน")
                }
            } else {
                Text("ลงเวลาครบแล้วสำหรับวันนี้", color = Color(0xFF027A48), fontWeight = FontWeight.SemiBold)
            }
            if (!canWriteAttendance) Text("แพ็กเกจหมดอายุ: ดูประวัติได้ แต่ลงเวลาใหม่ไม่ได้", color = MaterialTheme.colorScheme.error)
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}


@Composable
private fun SalaryDialog(
    employee: StoreEmployee,
    onDismiss: () -> Unit,
    onSave: suspend (Double, Double, Double, Double, Double, Double) -> Unit
) {
    val scope = rememberCoroutineScope()
    var base by remember { mutableStateOf(employee.baseSalary.toString()) }
    var wage by remember { mutableStateOf(employee.wageRate.toString()) }
    var overtime by remember { mutableStateOf(employee.overtimeHourlyRate.toString()) }
    var position by remember { mutableStateOf(employee.positionAllowance.toString()) }
    var regular by remember { mutableStateOf(employee.regularAllowance.toString()) }
    var social by remember { mutableStateOf(employee.socialSecurityAmount.toString()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("จัดการเงินเดือน • ${employee.fullName}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(base, { base = it }, label = { Text("เงินเดือนพื้นฐาน / เดือน") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                OutlinedTextField(wage, { wage = it }, label = { Text("ค่าแรงต่อวันหรือชั่วโมง") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                OutlinedTextField(overtime, { overtime = it }, label = { Text("ค่าล่วงเวลาต่อชั่วโมง") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                OutlinedTextField(position, { position = it }, label = { Text("ค่าตำแหน่ง") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                OutlinedTextField(regular, { regular = it }, label = { Text("เบี้ยเลี้ยงประจำ") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                OutlinedTextField(social, { social = it }, label = { Text("ประกันสังคม") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(enabled = !busy, onClick = {
                val values = listOf(base, wage, overtime, position, regular, social).map { it.toDoubleOrNull() }
                if (values.any { it == null || it < 0.0 }) error = "กรุณากรอกตัวเลขตั้งแต่ 0 ขึ้นไป"
                else scope.launch {
                    busy = true
                    try { onSave(values[0]!!, values[1]!!, values[2]!!, values[3]!!, values[4]!!, values[5]!!) }
                    catch (e: Exception) { error = e.message ?: "บันทึกเงินเดือนไม่สำเร็จ" }
                    finally { busy = false }
                }
            }) { Text(if (busy) "กำลังบันทึก..." else "บันทึก") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ยกเลิก") } }
    )
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
    repo: StoreFlowRepository, permissions: PlanPermissions,
    onUpgrade: () -> Unit, onSwitch: () -> Unit, onSignOut: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val canManage = role == "owner"
    val canManageQr = canManage && permissions.hasFeature(StoreFeature.STORE_PAYMENT_QR)
    var settings by remember(store.id) { mutableStateOf(StorePaymentSettings(store.id)) }
    var merchantQrBitmap by remember(store.id) { mutableStateOf<Bitmap?>(null) }
    var subscription by remember { mutableStateOf<StoreSubscription?>(null) }
    var promptPayId by remember { mutableStateOf("") }
    var promptPayName by remember { mutableStateOf("") }
    var bankName by remember { mutableStateOf("") }
    var bankAccountName by remember { mutableStateOf("") }
    var bankAccountNumber by remember { mutableStateOf("") }
    var inviteCode by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var deleteConfirm by remember { mutableStateOf(false) }
    var backupJson by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val exportBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri != null) scope.launch {
            try {
                val data = backupJson ?: error("ไม่มีข้อมูลสำรอง")
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray(Charsets.UTF_8)) }
                        ?: error("บันทึกไฟล์ไม่สำเร็จ")
                }
                message = "ส่งออกข้อมูลสำรองเรียบร้อย"
            } catch (e: Exception) { error = e.message ?: "ส่งออกข้อมูลไม่สำเร็จ" }
        }
    }
    val importBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) scope.launch {
            busy = true; error = null; message = null
            try {
                val data = withContext(Dispatchers.IO) {
                    val input = context.contentResolver.openInputStream(uri)
                        ?: error("อ่านไฟล์สำรองไม่สำเร็จ")
                    input.use { stream ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        var total = 0
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            total += count
                            require(total <= 8 * 1024 * 1024) { "ไฟล์สำรองต้องมีขนาดไม่เกิน 8 MB" }
                            output.write(buffer, 0, count)
                        }
                        String(output.toByteArray(), Charsets.UTF_8)
                    }
                }
                message = repo.importStoreBackup(store.id, data)
            } catch (e: Exception) { error = e.message ?: "นำเข้าข้อมูลไม่สำเร็จ" }
            finally { busy = false }
        }
    }
    val qrPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri != null) scope.launch {
            busy = true; error = null
            try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("อ่านรูป QR ไม่สำเร็จ")
                }
                val path = repo.uploadStoreQr(store.id, bytes)
                val updated = settings.copy(qrImagePath = path, customQrUrl = path)
                repo.saveStorePaymentSettings(updated)
                settings = updated
                merchantQrBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                message = "อัปโหลด QR ของร้านเรียบร้อย"
            } catch (e: Exception) { error = e.message ?: "อัปโหลด QR ไม่สำเร็จ" }
            finally { busy = false }
        }
    }

    LaunchedEffect(store.id) {
        runCatching {
            settings = repo.storePaymentSettings(store.id) ?: StorePaymentSettings(store.id)
            promptPayId = settings.promptpayId.orEmpty()
            promptPayName = settings.promptpayName.orEmpty()
            bankName = settings.bankName.orEmpty()
            bankAccountName = settings.bankAccountName.orEmpty()
            bankAccountNumber = settings.bankAccountNumber.orEmpty()
            val qrPath = settings.customQrUrl ?: settings.qrImagePath
            merchantQrBitmap = qrPath?.let { path ->
                runCatching {
                    val bytes = withContext(Dispatchers.IO) { repo.downloadStoreQr(path) }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }.getOrNull()
            }
            subscription = repo.subscription(store.id)
        }.onFailure { error = it.message ?: "โหลดการตั้งค่าไม่สำเร็จ" }
    }

    if (deleteConfirm) {
        AlertDialog(
            onDismissRequest = { if (!busy) deleteConfirm = false },
            title = { Text("ยืนยันลบบัญชีถาวร") },
            text = { Text("การลบบัญชีไม่สามารถย้อนกลับได้ ร้านที่คุณเป็นเจ้าของคนเดียวจะถูกลบทั้งร้านและไฟล์ที่เกี่ยวข้อง หากร้านมีเจ้าของร่วม ระบบจะเก็บร้านนั้นไว้ หากยังมีพนักงานแต่ไม่มีเจ้าของคนอื่น คุณต้องโอนสิทธิ์เจ้าของก่อน กรุณาส่งออกข้อมูลก่อนดำเนินการ") },
            confirmButton = {
                TextButton(enabled = !busy, onClick = {
                    scope.launch {
                        busy = true; error = null
                        try {
                            repo.deleteAccountPermanently()
                            deleteConfirm = false
                            onSignOut()
                        } catch (e: Exception) {
                            error = e.message ?: "ลบบัญชีไม่สำเร็จ"
                        } finally { busy = false }
                    }
                }) { Text(if (busy) "กำลังลบ..." else "ยืนยันลบบัญชี") }
            },
            dismissButton = { TextButton(onClick = { deleteConfirm = false }, enabled = !busy) { Text("ยกเลิก") } }
        )
    }
    LazyColumn(modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("ตั้งค่า", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold) }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Text("ร้านค้าที่ใช้งาน", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(store.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("สิทธิ์: $role")
                    Text(email, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(permissions.packageLabel, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary)
                    TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://benz-verse.com/storeflow-privacy"))) }) {
                        Text("นโยบายความเป็นส่วนตัวและ PDPA")
                    }
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ตั้งค่าการรับชำระเงิน", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    if (!canManage) Text("เฉพาะเจ้าของร้านเท่านั้นที่แก้ไขได้")
                    if (!permissions.hasFeature(StoreFeature.STORE_PAYMENT_QR)) {
                        Text("การตั้งค่า QR รับเงินต้องใช้แพ็กเกจ Standard ขึ้นไป",
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        TextButton(onClick = onUpgrade) { Text("อัปเกรดแพ็กเกจ") }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("เงินสด", Modifier.weight(1f)); Switch(settings.cashEnabled,
                            { settings = settings.copy(cashEnabled = it) }, enabled = canManage)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("PromptPay / QR", Modifier.weight(1f)); Switch(settings.promptpayEnabled,
                            { settings = settings.copy(promptpayEnabled = it) }, enabled = canManageQr)
                    }
                    OutlinedTextField(promptPayId, { promptPayId = it.filter(Char::isDigit) },
                        label = { Text("เบอร์พร้อมเพย์ 10 หลัก หรือเลขบัตร 13 หลัก") },
                        enabled = canManageQr, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(promptPayName, { promptPayName = it },
                        label = { Text("ชื่อบัญชีพร้อมเพย์") }, enabled = canManageQr,
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    HorizontalDivider()
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("โอนเข้าบัญชีธนาคาร", Modifier.weight(1f)); Switch(settings.bankTransferEnabled,
                            { settings = settings.copy(bankTransferEnabled = it) }, enabled = canManage)
                    }
                    OutlinedTextField(bankName, { bankName = it }, label = { Text("ธนาคาร") },
                        enabled = canManage, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(bankAccountName, { bankAccountName = it }, label = { Text("ชื่อบัญชี") },
                        enabled = canManage, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(bankAccountNumber, { bankAccountNumber = it }, label = { Text("เลขบัญชี") },
                        enabled = canManage, singleLine = true, modifier = Modifier.fillMaxWidth())
                    if (permissions.hasFeature(StoreFeature.STORE_PAYMENT_QR)) merchantQrBitmap?.let { Image(it.asImageBitmap(), contentDescription = "QR รับเงินของร้าน",
                        modifier = Modifier.fillMaxWidth().height(190.dp)) }
                    if (canManageQr) {
                        OutlinedButton(onClick = { qrPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                            enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Text(if (settings.customQrUrl == null && settings.qrImagePath == null) "อัปโหลด QR ประจำร้าน" else "เปลี่ยนรูป QR ประจำร้าน")
                        }
                        if (merchantQrBitmap != null) Text("QR นี้จะแสดงให้ลูกค้าในหน้าชำระเงิน POS", color = MaterialTheme.colorScheme.primary)
                    }
                    if (canManage) Button(
                        enabled = !busy && !permissions.isExpired,
                        onClick = {
                            scope.launch {
                                busy = true; error = null; message = null
                                try {
                                    require(!settings.promptpayEnabled || promptPayId.length == 10 || promptPayId.length == 13) {
                                        "กรุณากรอกเบอร์พร้อมเพย์ 10 หลัก หรือเลขบัตร 13 หลัก"
                                    }
                                    repo.saveStorePaymentSettings(settings.copy(
                                        promptpayId = promptPayId.ifBlank { null },
                                        promptpayName = promptPayName.ifBlank { null },
                                        bankName = bankName.ifBlank { null },
                                        bankAccountName = bankAccountName.ifBlank { null },
                                        bankAccountNumber = bankAccountNumber.ifBlank { null }
                                    ))
                                    message = "บันทึกการตั้งค่ารับชำระเงินแล้ว"
                                } catch (e: Exception) { error = e.message ?: "บันทึกไม่สำเร็จ" }
                                finally { busy = false }
                            }
                        }, modifier = Modifier.fillMaxWidth()
                    ) { Text(if (busy) "กำลังบันทึก..." else "บันทึกช่องทางรับเงิน") }
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("แพ็กเกจสมาชิก", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(permissions.packageLabel, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    Text("แพ็กเกจปัจจุบัน: " + (subscription?.planTier ?: subscription?.planId ?: "-").uppercase())
                    Text("สถานะ: " + (subscription?.status ?: "ยังไม่มีข้อมูล"))
                    Text("เลือก Basic, Standard, Premium หรือซื้อขาด และส่งสลิปได้จากเมนูแพ็กเกจ",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (canManage) item {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("รหัสเชิญพนักงาน", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    inviteCode?.let { Text(it, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold) }
                    OutlinedButton(onClick = {
                        scope.launch {
                            busy = true
                            try { inviteCode = repo.ownerInviteCode(); message = "สร้างรหัสเชิญแล้ว" }
                            catch (e: Exception) { error = e.message ?: "สร้างรหัสเชิญไม่สำเร็จ" }
                            finally { busy = false }
                        }
                    }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("สร้าง / แสดงรหัสเชิญ") }
                }
            }
        }
        if (canManage) item {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("สำรองและกู้คืนข้อมูลร้าน", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("ส่งออกข้อมูลร้านเป็น JSON หรือรวมข้อมูลจากไฟล์สำรองเข้าร้านนี้โดยไม่เขียนทับรายการเดิม ไฟล์สำรองมีข้อมูลลูกค้า พนักงาน เงินเดือน และเลขบัญชี ควรเก็บในที่ปลอดภัย")
                    OutlinedButton(enabled = !busy, onClick = {
                        scope.launch {
                            busy = true; error = null
                            try {
                                backupJson = repo.exportStoreBackup(store.id)
                                exportBackupLauncher.launch("StoreFlow-${store.id}-backup.json")
                            } catch (e: Exception) { error = e.message ?: "สำรองข้อมูลไม่สำเร็จ" }
                            finally { busy = false }
                        }
                    }, modifier = Modifier.fillMaxWidth()) { Text("ส่งออกข้อมูล JSON") }
                    OutlinedButton(enabled = !busy, onClick = {
                        importBackupLauncher.launch(arrayOf("application/json", "text/json"))
                    }, modifier = Modifier.fillMaxWidth()) { Text("นำเข้าข้อมูล JSON") }
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("บัญชีและความเป็นส่วนตัว", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW,
                            Uri.parse("https://songpon3327ppumusic-ops.github.io/Pos/privacy/")))
                    }, modifier = Modifier.fillMaxWidth()) { Text("อ่านนโยบายความเป็นส่วนตัว") }
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW,
                            Uri.parse("https://songpon3327ppumusic-ops.github.io/Pos/account-deletion/")))
                    }, modifier = Modifier.fillMaxWidth()) { Text("เปิดหน้าเว็บขอลบบัญชี") }
                    Button(onClick = { deleteConfirm = true }, modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFB42318))) {
                        Text("ลบบัญชีและข้อมูลที่เกี่ยวข้องถาวร")
                    }
                    Text("หากเป็นเจ้าของร้าน ระบบจะลบข้อมูลร้านที่คุณเป็นเจ้าของด้วย ส่วนประวัติธุรกรรมของร้านอื่นที่คุณเคยทำงานจะเก็บไว้โดยไม่ระบุตัวบัญชี",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        item { OutlinedButton(onClick = onSwitch, modifier = Modifier.fillMaxWidth()) { Text("เปลี่ยนร้านค้า") } }
        item {
            Button(onClick = onSignOut, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFB42318))) { Text("ออกจากระบบ") }
        }
        message?.let { item { Text(it, color = MaterialTheme.colorScheme.primary) } }
        error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
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

package com.storeflow.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.storeflow.app.ui.theme.StoreFlowTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { StoreFlowTheme { StoreFlowRoot() } }
    }
}

private data class Destination(val label: String, val icon: ImageVector)
private val destinations = listOf(
    Destination("ภาพรวม", Icons.Default.Storefront),
    Destination("ขาย", Icons.Default.PointOfSale),
    Destination("สินค้า", Icons.Default.Inventory2),
    Destination("รายงาน", Icons.Default.BarChart),
    Destination("ตั้งค่า", Icons.Default.Settings)
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StoreFlowRoot() {
    var selected by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        containerColor = Color(0xFFF6F8FB),
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("StoreFlow", fontWeight = FontWeight.Bold)
                        Text("ระบบจัดการร้านค้า", style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color(0xFFF6F8FB))
            )
        },
        bottomBar = {
            NavigationBar(containerColor = Color.White) {
                destinations.forEachIndexed { index, item ->
                    NavigationBarItem(
                        selected = selected == index,
                        onClick = { selected = index },
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        label = { Text(item.label) }
                    )
                }
            }
        }
    ) { padding ->
        when (selected) {
            0 -> DashboardScreen(Modifier.padding(padding))
            1 -> EmptyModule("ระบบขายหน้าร้าน", "เตรียมเชื่อมตะกร้าสินค้า การชำระเงิน และการเปิดกะ")
            2 -> EmptyModule("สินค้าและสต็อก", "เตรียมเชื่อมสินค้า บาร์โค้ด และการปรับสต็อก")
            3 -> EmptyModule("รายงาน", "รายงานจะแสดงจากข้อมูลจริงใน Supabase")
            else -> EmptyModule("ตั้งค่า", "บัญชีร้านค้า สมาชิก และช่องทางชำระเงิน")
        }
    }
}

@Composable
private fun DashboardScreen(modifier: Modifier = Modifier) {
    LazyColumn(modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Spacer(Modifier.height(8.dp))
            Text("ภาพรวมร้านค้า", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("ข้อมูลจะโหลดจากบัญชีร้านค้าของคุณ", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF123C35))) {
                Column(Modifier.padding(22.dp)) {
                    Text("ยอดขายวันนี้", color = Color(0xFFD1E9E2))
                    Spacer(Modifier.height(8.dp))
                    Text("ยังไม่ได้เชื่อมข้อมูล", color = Color.White,
                        style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text("เข้าสู่ระบบเพื่อดูยอดขายจริง", color = Color(0xFFD1E9E2))
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MetricCard("คำสั่งซื้อ", "—", Modifier.weight(1f))
                MetricCard("สินค้าใกล้หมด", "—", Modifier.weight(1f))
            }
        }
        item {
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(Modifier.padding(18.dp)) {
                    Text("เริ่มต้นใช้งาน", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    Text("1. เข้าสู่ระบบด้วยบัญชี StoreFlow")
                    Text("2. เลือกร้านค้าที่ต้องการจัดการ")
                    Text("3. เริ่มขายและจัดการสต็อก")
                }
            }
        }
        item { Spacer(Modifier.height(8.dp)) }
    }
}

@Composable
private fun MetricCard(title: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier, shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(Modifier.padding(16.dp)) {
            Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(10.dp))
            Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun EmptyModule(title: String, description: String) {
    Column(Modifier.fillMaxSize().background(Color(0xFFF6F8FB)).padding(24.dp),
        verticalArrangement = Arrangement.Center) {
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text(description, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

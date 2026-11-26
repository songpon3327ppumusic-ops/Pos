package com.storeflow.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val StoreFlowColors = lightColorScheme(
    primary = Color(0xFF0F766E),
    onPrimary = Color.White,
    secondary = Color(0xFF0D9488),
    background = Color(0xFFF6F8FB),
    surface = Color.White,
    onSurface = Color(0xFF17212B),
    onSurfaceVariant = Color(0xFF64748B),
    outline = Color(0xFFE2E8F0)
)

@Composable
fun StoreFlowTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = StoreFlowColors, content = content)
}

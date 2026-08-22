package com.sonnguyenhoang.game2048.ui.theme

import android.app.Activity
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val AppColors = lightColorScheme(primary = Accent, onPrimary = Color.White, background = Paper, onBackground = Ink, surface = Paper, onSurface = Ink)

@Composable
fun Game2048Theme(content: @Composable () -> Unit) {
    val view = LocalView.current
    if (!view.isInEditMode) SideEffect {
        val window = (view.context as Activity).window
        window.statusBarColor = Paper.toArgb(); window.navigationBarColor = Paper.toArgb()
        WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = true
        WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = true
    }
    MaterialTheme(colorScheme = AppColors, typography = AppTypography, content = content)
}

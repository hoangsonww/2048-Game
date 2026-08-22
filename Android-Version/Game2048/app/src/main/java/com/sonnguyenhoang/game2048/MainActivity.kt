package com.sonnguyenhoang.game2048

import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Swipe
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sonnguyenhoang.game2048.ui.theme.*
import kotlin.math.abs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { Game2048Theme { GameScreen() } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GameScreen(providedViewModel: GameViewModel? = null) {
    val context = LocalContext.current
    val viewModel = providedViewModel ?: remember { GameViewModel(SharedPreferencesGameStorage(context.getSharedPreferences("game_2048", 0))) }
    val haptics = LocalHapticFeedback.current
    var showHelp by remember { mutableStateOf(false) }
    var confirmRestart by remember { mutableStateOf(false) }
    var dismissWin by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize().background(Paper)) {
        GridTexture()
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Header(onHelp = { showHelp = true })
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text("Make space.", fontSize = 42.sp, lineHeight = 44.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1.8).sp, color = Ink)
                Text("Find 2048.", fontSize = 38.sp, lineHeight = 42.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, letterSpacing = (-1.4).sp, color = Accent)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                ScoreCard("Score", viewModel.score, true, Modifier.weight(1f))
                ScoreCard("Best", viewModel.highScore, false, Modifier.weight(1f))
            }
            GameBoard(
                grid = viewModel.grid,
                gameOver = viewModel.isGameOver(),
                showWin = viewModel.hasWon && !dismissWin,
                score = viewModel.score,
                onSwipe = { direction ->
                    val moved = viewModel.swipe(direction)
                    haptics.performHapticFeedback(if (moved) HapticFeedbackType.TextHandleMove else HapticFeedbackType.LongPress)
                },
                onRestart = { viewModel.restartGame(); dismissWin = false },
                onContinue = { dismissWin = true }
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GameAction("Undo", Icons.AutoMirrored.Rounded.Undo, !viewModel.canUndo, Modifier.weight(1f)) { viewModel.undo(); haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
                GameAction("New game", Icons.Rounded.Refresh, false, Modifier.weight(1f)) { if (viewModel.score > 0) confirmRestart = true else viewModel.restartGame() }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Swipe, contentDescription = null, tint = Muted, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(7.dp))
                Text("Swipe anywhere on the board to move", color = Muted, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            }
            Spacer(Modifier.height(10.dp))
        }
    }

    if (confirmRestart) AlertDialog(
        onDismissRequest = { confirmRestart = false },
        icon = { Icon(Icons.Rounded.Refresh, contentDescription = null, tint = Accent, modifier = Modifier.size(24.dp)) },
        title = { Text("Start a fresh board?", fontWeight = FontWeight.Bold) },
        text = { Text("Your best score stays safe, but this round will be replaced.") },
        confirmButton = { Button(onClick = { viewModel.restartGame(); dismissWin = false; confirmRestart = false }, colors = ButtonDefaults.buttonColors(containerColor = Accent)) { Text("New game") } },
        dismissButton = { TextButton(onClick = { confirmRestart = false }) { Text("Keep playing") } }
    )

    if (showHelp) ModalBottomSheet(onDismissRequest = { showHelp = false }, containerColor = Paper) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 36.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Small rules.\nDeep decisions.", fontSize = 36.sp, lineHeight = 38.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1.4).sp, color = Ink)
            HelpRow("01", "Slide", "Swipe the board to move every tile in one direction.")
            HelpRow("02", "Match", "Equal tiles merge and add their new value to your score.")
            HelpRow("03", "Protect space", "Keep your largest tile in a corner and preserve empty cells.")
            Button(onClick = { showHelp = false }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Ink)) { Text("Got it") }
        }
    }
}

@Composable
private fun GridTexture() {
    Canvas(Modifier.fillMaxSize()) {
        val spacing = 44.dp.toPx(); val stroke = 0.6.dp.toPx()
        var x = 0f
        while (x <= size.width) { drawLine(GridLine, Offset(x, 0f), Offset(x, size.height), stroke); x += spacing }
        var y = 0f
        while (y <= size.height) { drawLine(GridLine, Offset(0f, y), Offset(size.width, y), stroke); y += spacing }
    }
}

@Composable
private fun Header(onHelp: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        BrandMark(Modifier.size(36.dp)); Spacer(Modifier.width(10.dp))
        Text("2048", color = Ink, fontSize = 19.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp)
        Spacer(Modifier.weight(1f))
        IconButton(onClick = onHelp, modifier = Modifier.size(44.dp).background(Color.White.copy(alpha = 0.68f), RoundedCornerShape(13.dp))) { Icon(Icons.AutoMirrored.Rounded.HelpOutline, contentDescription = "How to play", modifier = Modifier.size(22.dp), tint = Ink) }
    }
}

@Composable
private fun BrandMark(modifier: Modifier = Modifier) {
    Box(modifier.clip(RoundedCornerShape(10.dp)).background(Ink).padding(9.dp)) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(3.dp)) { Box(Modifier.weight(1f).fillMaxHeight().background(Color.White, RoundedCornerShape(1.dp))); Box(Modifier.weight(1f).fillMaxHeight().background(Color.White, RoundedCornerShape(1.dp))) }
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(3.dp)) { Box(Modifier.weight(1f).fillMaxHeight().background(Color.White, RoundedCornerShape(1.dp))); Box(Modifier.weight(1f).fillMaxHeight().background(Accent, RoundedCornerShape(1.dp))) }
        }
    }
}

@Composable
private fun ScoreCard(label: String, value: Int, dark: Boolean, modifier: Modifier = Modifier) {
    Column(modifier.semantics { contentDescription = "$label: $value" }.background(if (dark) Ink else Color.White.copy(alpha = 0.68f), RoundedCornerShape(14.dp)).padding(horizontal = 15.dp, vertical = 11.dp)) {
        Text(label.uppercase(), color = if (dark) Color.White.copy(alpha = 0.62f) else Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        Text("%,d".format(value), color = if (dark) Color.White else Ink, fontFamily = FontFamily.Monospace, fontSize = 27.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-1.4).sp)
    }
}

@Composable
private fun GameBoard(grid: List<List<Int>>, gameOver: Boolean, showWin: Boolean, score: Int, onSwipe: (GameViewModel.Direction) -> Unit, onRestart: () -> Unit, onContinue: () -> Unit) {
    var drag by remember { mutableStateOf(Offset.Zero) }
    BoxWithConstraints(
        modifier = Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(19.dp)).background(Board).padding(10.dp)
            .pointerInput(Unit) {
                detectDragGestures(onDragStart = { drag = Offset.Zero }, onDragEnd = {
                    if (maxOf(abs(drag.x), abs(drag.y)) >= 36f) onSwipe(if (abs(drag.x) > abs(drag.y)) if (drag.x > 0) GameViewModel.Direction.RIGHT else GameViewModel.Direction.LEFT else if (drag.y > 0) GameViewModel.Direction.DOWN else GameViewModel.Direction.UP)
                    drag = Offset.Zero
                }, onDragCancel = { drag = Offset.Zero }, onDrag = { change, amount ->
                    // Consume the change so the enclosing verticalScroll does not also
                    // act on it. Without this a board swipe scrolls the whole screen.
                    change.consume()
                    drag += amount
                })
            }.semantics { contentDescription = "2048 game board" }
    ) {
        val gap = 8.dp; val tile = (maxWidth - gap * 3) / 4
        Column(verticalArrangement = Arrangement.spacedBy(gap)) { grid.forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(gap)) { row.forEach { value -> Tile(value, Modifier.size(tile)) } } } }
        // Fades in like the web overlay's `fade-in .25s` keyframe.
        val overlayFade = if (animationsEnabled()) tween<Float>(250) else snap()
        AnimatedVisibility(visible = gameOver, enter = fadeIn(overlayFade), exit = fadeOut(overlayFade)) {
            EndPanel("Round complete", "No more moves", "Final score: %,d".format(score), "Try again", null, onRestart, null)
        }
        AnimatedVisibility(visible = !gameOver && showWin, enter = fadeIn(overlayFade), exit = fadeOut(overlayFade)) {
            EndPanel("Goal reached", "You made 2048", "Keep building, or start with a clean board.", "New game", "Keep playing", onRestart, onContinue)
        }
    }
}

/**
 * A tile that animates the way the web and iOS clients do: the background
 * colour eases between values, and a tile that gains a value pops from 82% to
 * full size on a spring. Matches the web `.cell` transition and `pop` keyframe.
 *
 * Both animations collapse to instant when the system animation scale is off,
 * which is the Android equivalent of `prefers-reduced-motion`.
 */
@Composable
private fun Tile(value: Int, modifier: Modifier = Modifier) {
    val animated = animationsEnabled()
    val color by animateColorAsState(
        targetValue = tileColor(value),
        animationSpec = if (animated) tween(durationMillis = 180) else snap(),
        label = "tileColor"
    )
    val scale = remember { Animatable(1f) }
    var previous by remember { mutableIntStateOf(value) }

    LaunchedEffect(value) {
        if (value != previous && value > 0 && animated) {
            scale.snapTo(0.82f)
            scale.animateTo(1f, spring(dampingRatio = 0.52f, stiffness = 620f))
        } else {
            scale.snapTo(1f)
        }
        previous = value
    }

    Box(
        modifier
            .graphicsLayer { scaleX = scale.value; scaleY = scale.value }
            .background(color, RoundedCornerShape(11.dp)),
        contentAlignment = Alignment.Center
    ) {
        AnimatedContent(
            targetState = value,
            transitionSpec = {
                if (animated) {
                    (fadeIn(tween(140)) + scaleIn(tween(140), initialScale = 0.7f))
                        .togetherWith(fadeOut(tween(90)))
                } else {
                    fadeIn(snap()).togetherWith(fadeOut(snap()))
                }
            },
            label = "tileValue"
        ) { shown ->
            if (shown > 0) {
                Text(
                    "%,d".format(shown),
                    color = if (shown >= 8) Color.White else TileInk,
                    fontFamily = FontFamily.Monospace,
                    fontSize = when { shown >= 1024 -> 24.sp; shown >= 128 -> 28.sp; else -> 34.sp },
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-1.6).sp,
                    maxLines = 1
                )
            }
        }
    }
}

/**
 * False when the user has turned system animations off (Developer options, or
 * the Remove animations accessibility setting). Compose has no direct
 * equivalent of `prefers-reduced-motion`, so read the platform scale.
 */
@Composable
private fun animationsEnabled(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f
    }
}

@Composable
private fun GameAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, disabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = !disabled, modifier = modifier.height(50.dp), shape = RoundedCornerShape(13.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink, disabledContentColor = Muted.copy(alpha = 0.55f))) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text(title, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun EndPanel(kicker: String, title: String, detail: String, primary: String, secondary: String?, primaryAction: () -> Unit, secondaryAction: (() -> Unit)?) {
    Column(Modifier.fillMaxSize().background(Ink.copy(alpha = 0.95f), RoundedCornerShape(13.dp)).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(kicker.uppercase(), color = CoralLight, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.1.sp); Spacer(Modifier.height(7.dp))
        Text(title, color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1.2).sp); Spacer(Modifier.height(7.dp))
        Text(detail, color = Color.White.copy(alpha = 0.72f), fontSize = 14.sp, textAlign = TextAlign.Center); Spacer(Modifier.height(15.dp))
        Row(verticalAlignment = Alignment.CenterVertically) { Button(onClick = primaryAction, colors = ButtonDefaults.buttonColors(containerColor = Accent)) { Text(primary) }; if (secondary != null && secondaryAction != null) { Spacer(Modifier.width(10.dp)); TextButton(onClick = secondaryAction, colors = ButtonDefaults.textButtonColors(contentColor = Color.White)) { Text(secondary) } } }
    }
}

@Composable
private fun HelpRow(number: String, title: String, detail: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) { Text(number, color = Accent, fontFamily = FontFamily.Monospace, fontSize = 12.sp); Spacer(Modifier.width(18.dp)); Column { Text(title, color = Ink, fontWeight = FontWeight.Bold, fontSize = 17.sp); Spacer(Modifier.height(4.dp)); Text(detail, color = Muted, lineHeight = 22.sp) } }
}

private fun tileColor(value: Int) = when (value) { 0 -> EmptyTile; 2 -> Tile2; 4 -> Tile4; 8 -> Tile8; 16 -> Tile16; 32 -> Tile32; 64 -> Tile64; 128 -> Tile128; 256 -> Tile256; 512 -> Tile512; 1024 -> Tile1024; else -> Ink }

@Preview(showBackground = true, showSystemUi = true)
@Composable
private fun GamePreview() { Game2048Theme { GameScreen() } }

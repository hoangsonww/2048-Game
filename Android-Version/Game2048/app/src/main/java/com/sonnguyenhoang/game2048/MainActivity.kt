package com.sonnguyenhoang.game2048

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlin.math.abs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            GameScreen()
        }
    }
}

@Composable
fun GameScreen() {
    val viewModel = remember { GameViewModel() }

    LaunchedEffect(key1 = Unit) {
        viewModel.initializeGame()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(6.dp))
        Text(text = "2048", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(6.dp))
        Text(text = "Join the numbers and get to the 2048 tile!")
        Spacer(modifier = Modifier.height(20.dp))
        Text(text = "Score: ${viewModel.score}")
        Text(text = "High Score: ${viewModel.highScore}")

        Spacer(modifier = Modifier.height(16.dp))

        val gridSize = viewModel.gridSize
        val grid = viewModel.grid

        // Detect swipes and move tiles
        Box(
            modifier = Modifier
                .background(Color.LightGray)
                .padding(8.dp)
                .pointerInput(Unit) {
                    detectDragGestures { change, dragAmount ->
                        val (dragX, dragY) = dragAmount
                        Log.d("Swipe", "Drag amount: x=$dragX, y=$dragY")
                        when {
                            abs(dragX) > 50 -> {
                                Log.d("Swipe", "Horizontal swipe detected")
                                if (dragX > 0) viewModel.swipe(GameViewModel.Direction.RIGHT)
                                else viewModel.swipe(GameViewModel.Direction.LEFT)
                            }
                            abs(dragY) > 50 -> {
                                Log.d("Swipe", "Vertical swipe detected")
                                if (dragY > 0) viewModel.swipe(GameViewModel.Direction.DOWN)
                                else viewModel.swipe(GameViewModel.Direction.UP)
                            }
                        }
                    }
                }
        ) {
            Column {
                for (x in 0 until gridSize) {
                    Row {
                        for (y in 0 until gridSize) {
                            Box(
                                modifier = Modifier
                                    .size(70.dp)
                                    .background(getColorForValue(grid[x][y]))
                                    .padding(8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = if (grid[x][y] == 0) "" else grid[x][y].toString(),
                                    style = MaterialTheme.typography.bodyLarge
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

fun getColorForValue(value: Int): Color {
    return when (value) {
        2 -> Color(0xFFFFE4C4) // Bisque
        4 -> Color(0xFFFFEBCD) // BlanchedAlmond
        8 -> Color(0xFFFFA07A) // LightSalmon
        16 -> Color(0xFFFF8C00) // DarkOrange
        32 -> Color(0xFFFF4500) // OrangeRed
        64 -> Color(0xFFFF0000) // Red
        128 -> Color(0xFFF0E68C) // Khaki
        256 -> Color(0xFFADD8E6) // LightBlue
        512 -> Color(0xFF87CEEB) // SkyBlue
        1024 -> Color(0xFF6A5ACD) // SlateBlue
        2048 -> Color(0xFF800080) // Purple
        else -> Color(0xFFCDCDCD) // LightGray for others
    }
}

@Preview(showBackground = true)
@Composable
fun DefaultPreview() {
    GameScreen()
}

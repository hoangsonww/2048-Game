package com.sonnguyenhoang.game2048.cloud

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Leaderboard
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sonnguyenhoang.game2048.ui.theme.Accent
import com.sonnguyenhoang.game2048.ui.theme.Ink
import com.sonnguyenhoang.game2048.ui.theme.Muted
import kotlinx.coroutines.delay
import com.sonnguyenhoang.game2048.ui.theme.Paper

/**
 * The account, sync, and leaderboard surface for the Compose client.
 *
 * Every composable here is additive: with the cloud controller absent the
 * screen renders exactly the game it did before accounts existed. Colours and
 * type come from the shared design tokens so the surface reads as part of the
 * app rather than as a bolted-on account screen — see ARCHITECTURE.md,
 * "Design tokens, shared by hand".
 */

/**
 * The header's account control: a name when signed in, an invitation when not.
 *
 * Shaped like the icon buttons beside it — same 44dp height, same translucent
 * white fill, same corner radius — because a bare text button next to three
 * chips reads as something that was forgotten rather than something that
 * belongs. It is wider than they are, so it takes a pill.
 */
@Composable
fun AccountButton(controller: CloudController, onOpen: () -> Unit) {
    val label = controller.user?.displayName ?: "Sign in"
    Row(
        modifier = Modifier
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(Color.White.copy(alpha = 0.68f))
            .clickable(onClick = onOpen)
            .padding(start = 12.dp, end = 15.dp)
            .semantics { contentDescription = if (controller.isSignedIn) "Account: $label" else "Sign in or create an account" },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Rounded.Person, contentDescription = null, tint = Ink, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(7.dp))
        Text(
            label,
            color = Ink,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.widthIn(max = 104.dp)
        )
    }
}

@Composable
fun LeaderboardButton(onOpen: () -> Unit) {
    IconButton(
        onClick = onOpen,
        modifier = Modifier.size(44.dp).background(Color.White.copy(alpha = 0.68f), RoundedCornerShape(13.dp))
    ) {
        Icon(Icons.Rounded.Leaderboard, contentDescription = "Leaderboard", modifier = Modifier.size(22.dp), tint = Ink)
    }
}

/**
 * Temporary guest invite toast.
 *
 * Floats over the board for a few seconds on launch, then hides. Explicit
 * dismiss still persists via [onDismiss]. Never takes layout space from the
 * game column — that was pushing the board off the first screen.
 */
@Composable
fun GuestInviteToast(
    visible: Boolean,
    onCreate: () -> Unit,
    onSignIn: () -> Unit,
    onDismiss: () -> Unit,
    durationMs: Long = 5_500L
) {
    var showing by remember(visible) { mutableStateOf(visible) }

    LaunchedEffect(visible) {
        if (!visible) {
            showing = false
            return@LaunchedEffect
        }
        showing = true
        delay(durationMs)
        showing = false
        // Session-only hide: do not call onDismiss (that persists forever).
        // Parent should stop re-passing visible=true for this launch — see MainActivity.
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 20.dp),
        contentAlignment = Alignment.BottomCenter
    ) {
        AnimatedVisibility(
            visible = showing,
            enter = fadeIn() + scaleIn(initialScale = 0.96f),
            exit = fadeOut()
        ) {
            GuestPrompt(onCreate = onCreate, onSignIn = onSignIn, onDismiss = {
                showing = false
                onDismiss()
            })
        }
    }
}

/**
 * The guest invitation.
 *
 * It says what the player gets, not what they are missing, and it can always
 * be dismissed. The board behind it was fully playable the whole time.
 */
@Composable
fun GuestPrompt(onCreate: () -> Unit, onSignIn: () -> Unit, onDismiss: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.96f))
            .padding(start = 14.dp, top = 12.dp, end = 8.dp, bottom = 12.dp)
            .semantics { contentDescription = "Guest invite toast" },
        verticalAlignment = Alignment.Top
    ) {
        Column(Modifier.weight(1f)) {
            Text("Playing as a guest", color = Ink, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Text(
                "Create a free account to keep your board and best score on every device.",
                color = Muted,
                fontSize = 12.5.sp,
                lineHeight = 17.sp
            )
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = onCreate,
                    colors = ButtonDefaults.buttonColors(containerColor = Accent),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    modifier = Modifier.semantics { contentDescription = "Open create account" }
                ) { Text("Create account", fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
                TextButton(
                    onClick = onSignIn,
                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
                    modifier = Modifier.semantics { contentDescription = "Open sign in" }
                ) {
                    Text("Sign in", color = Ink, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        IconButton(onClick = onDismiss, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Rounded.Close, contentDescription = "Dismiss this suggestion", tint = Muted, modifier = Modifier.size(18.dp))
        }
    }
}

/**
 * The sync status under the board.
 *
 * Centred and quieter than the swipe hint above it, so the two read as one
 * block of secondary text. Left-aligned and full size it looked like a
 * caption that had come loose from something else.
 */
@Composable
fun CloudStatusLine(controller: CloudController) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (controller.isBusy && controller.activity != CloudController.Activity.LOADING_LEADERBOARD) {
            CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 1.5.dp, color = Muted)
            Spacer(Modifier.width(8.dp))
        }
        Text(
            controller.status,
            color = Muted.copy(alpha = 0.82f),
            fontSize = 11.5.sp,
            lineHeight = 16.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { contentDescription = "Sync status: ${controller.status}" }
        )
    }
}

enum class AuthMode { REGISTER, LOGIN }

/**
 * Sign-up and sign-in in one sheet.
 *
 * Two dialogs would double the surface for one decision a player makes once;
 * swapping the fields keeps the flow to a single place they can change their
 * mind inside.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthSheet(
    controller: CloudController,
    initialMode: AuthMode,
    onDismiss: () -> Unit,
    onRegister: (String, String, String) -> Unit,
    onLogin: (String, String) -> Unit,
    /** Whether a round is on screen that signing in will take off it. */
    handsOverRound: Boolean = false,
    onForgotPassword: () -> Unit = {}
) {
    var mode by remember { mutableStateOf(initialMode) }
    var username by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var identifier by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var mismatch by remember { mutableStateOf(false) }
    var confirmingHandover by remember { mutableStateOf(false) }

    val registering = mode == AuthMode.REGISTER
    val authenticating = controller.activity == CloudController.Activity.AUTHENTICATING
    // Sign-in has nothing to confirm: a mistyped password there is reported
    // by the server at once.
    val passwordsDisagree = registering && password != confirmPassword
    val submit = {
        if (registering) onRegister(username, email, password) else onLogin(identifier, password)
    }
    val attempt = {
        if (passwordsDisagree) {
            mismatch = true
        } else {
            mismatch = false
            if (handsOverRound) confirmingHandover = true else submit()
        }
    }

    if (confirmingHandover) HandoverDialog(
        registering = registering,
        onConfirm = { confirmingHandover = false; submit() },
        onDismiss = { confirmingHandover = false }
    )

    // Once the controller reports a signed-in session the sheet has done its
    // job; leaving it up would make a player dismiss a form that succeeded.
    LaunchedEffect(controller.isSignedIn) {
        if (controller.isSignedIn) onDismiss()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Paper) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                if (registering) "Create your account" else "Welcome back",
                fontSize = 28.sp,
                lineHeight = 32.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-1.1).sp,
                color = Ink
            )
            Text(
                when {
                    handsOverRound && registering ->
                        "Your account starts on a clean board. This round stays saved on this device and comes back when you sign out."
                    handsOverRound ->
                        "Signing in loads the round saved to your account. This round stays on this device and comes back when you sign out."
                    registering -> "Keep your board, best score, and streak on every device you play on."
                    else -> "Sign in to pick up the round you left on another device."
                },
                color = Muted,
                fontSize = 14.sp,
                lineHeight = 19.sp,
                modifier = Modifier.semantics { contentDescription = "Sign-in intro" }
            )

            controller.authError?.let { message ->
                Text(
                    message,
                    color = Accent,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Accent.copy(alpha = 0.12f))
                        .padding(12.dp)
                        .semantics { contentDescription = "Sign-in problem: $message" }
                )
            }

            if (registering) {
                CloudTextField(username, { username = it }, "Username", KeyboardType.Text, enabled = !authenticating)
                CloudTextField(email, { email = it }, "Email", KeyboardType.Email, enabled = !authenticating)
            } else {
                CloudTextField(identifier, { identifier = it }, "Username or email", KeyboardType.Text, enabled = !authenticating)
            }
            CloudTextField(password, { password = it }, "Password", KeyboardType.Password, isPassword = true, enabled = !authenticating)
            if (registering) {
                CloudTextField(
                    confirmPassword,
                    { confirmPassword = it },
                    "Confirm password",
                    KeyboardType.Password,
                    isPassword = true,
                    enabled = !authenticating
                )
            }
            if (mismatch && passwordsDisagree) {
                Text(
                    "Those passwords do not match.",
                    color = Accent,
                    fontSize = 12.sp,
                    modifier = Modifier.semantics { contentDescription = "Those passwords do not match." }
                )
            } else {
                Text(
                    "At least 8 characters, including one letter and one number.",
                    color = Muted,
                    fontSize = 11.5.sp
                )
            }

            Button(
                onClick = {
                    // Nothing to lose, nothing to ask. A played round is warned
                    // about before it leaves the screen.
                    attempt()
                },
                enabled = !authenticating,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = if (authenticating) {
                            if (registering) "Creating account" else "Signing in"
                        } else if (registering) "Submit create account" else "Submit sign in"
                    },
                colors = ButtonDefaults.buttonColors(containerColor = Accent)
            ) {
                if (authenticating) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                    Spacer(Modifier.width(10.dp))
                    Text(if (registering) "Creating account…" else "Signing in…", fontWeight = FontWeight.Bold)
                } else {
                    Text(if (registering) "Create account" else "Sign in", fontWeight = FontWeight.Bold)
                }
            }

            TextButton(
                onClick = {
                    controller.clearAuthError()
                    mismatch = false
                    confirmPassword = ""
                    mode = if (registering) AuthMode.LOGIN else AuthMode.REGISTER
                },
                enabled = !authenticating,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    if (registering) "I already have an account" else "Create an account instead",
                    color = Muted,
                    fontSize = 13.sp
                )
            }

            TextButton(
                onClick = {
                    controller.clearAuthError()
                    onForgotPassword()
                },
                enabled = !authenticating,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Open password reset" }
            ) {
                Text("Forgot your password?", color = Muted, fontSize = 13.sp)
            }
        }
    }
}

/**
 * Password reset, without an email round trip.
 *
 * Confirming the username and the address on the account is the whole proof
 * — see the security note on the endpoint in
 * `server/src/routes/auth.routes.js`. The sheet says plainly that every
 * device will be signed out, because that is what happens and a player
 * should not discover it afterwards.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ResetPasswordSheet(
    controller: CloudController,
    onDismiss: () -> Unit,
    onReset: (String, String, String) -> Unit
) {
    var username by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var mismatch by remember { mutableStateOf(false) }

    val working = controller.activity == CloudController.Activity.AUTHENTICATING
    val passwordsDisagree = password != confirmPassword

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Paper) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "Reset your password",
                fontSize = 28.sp,
                lineHeight = 32.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-1.1).sp,
                color = Ink
            )
            Text(
                "Confirm the username and email on the account, then choose a new password. Every device signed in to it will be signed out.",
                color = Muted,
                fontSize = 14.sp,
                lineHeight = 19.sp,
                modifier = Modifier.semantics { contentDescription = "Password reset intro" }
            )

            controller.authError?.let { message ->
                Text(
                    message,
                    color = Accent,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Accent.copy(alpha = 0.12f))
                        .padding(12.dp)
                        .semantics { contentDescription = "Reset problem: $message" }
                )
            }

            CloudTextField(username, { username = it }, "Username", KeyboardType.Text, enabled = !working)
            CloudTextField(email, { email = it }, "Email", KeyboardType.Email, enabled = !working)
            CloudTextField(password, { password = it }, "New password", KeyboardType.Password, isPassword = true, enabled = !working)
            CloudTextField(confirmPassword, { confirmPassword = it }, "Confirm new password", KeyboardType.Password, isPassword = true, enabled = !working)

            if (mismatch && passwordsDisagree) {
                Text(
                    "Those passwords do not match.",
                    color = Accent,
                    fontSize = 12.sp,
                    modifier = Modifier.semantics { contentDescription = "Those passwords do not match." }
                )
            } else {
                Text("At least 8 characters, including one letter and one number.", color = Muted, fontSize = 11.5.sp)
            }

            Button(
                onClick = {
                    if (passwordsDisagree) {
                        mismatch = true
                    } else {
                        mismatch = false
                        onReset(username, email, password)
                    }
                },
                enabled = !working,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = if (working) "Resetting password" else "Submit password reset" },
                colors = ButtonDefaults.buttonColors(containerColor = Accent)
            ) {
                if (working) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                    Spacer(Modifier.width(10.dp))
                    Text("Resetting…", fontWeight = FontWeight.Bold)
                } else {
                    Text("Reset password", fontWeight = FontWeight.Bold)
                }
            }

            TextButton(
                onClick = onDismiss,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Back to sign in" }
            ) {
                Text("Back to sign in", color = Muted, fontSize = 13.sp)
            }
        }
    }
}

/** The warning shown before a sign-in takes the current board off the screen. */
@Composable
private fun HandoverDialog(registering: Boolean, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Set this round aside?", fontWeight = FontWeight.Bold) },
        text = {
            Text(
                if (registering) {
                    "Your new account starts on a clean board. This round stays saved on this device and comes back the moment you sign out."
                } else {
                    "Your account keeps its own board. This round stays saved on this device and comes back the moment you sign out."
                }
            )
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(containerColor = Accent),
                modifier = Modifier.semantics { contentDescription = "Continue signing in" }
            ) { Text("Continue") }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                modifier = Modifier.semantics { contentDescription = "Keep playing this round" }
            ) { Text("Keep playing") }
        }
    )
}

/**
 * A text field, with an in-field reveal control when it holds a password.
 *
 * A password a player cannot read is a password they mistype, and retyping
 * it into a confirmation field they also cannot read does not help. The
 * toggle is per field, so revealing one does not expose the rest of the form
 * to whoever is standing behind them.
 */
@Composable
private fun CloudTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    keyboardType: KeyboardType,
    isPassword: Boolean = false,
    enabled: Boolean = true
) {
    var revealed by remember { mutableStateOf(false) }
    val hidden = isPassword && !revealed

    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = label },
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Next),
        visualTransformation = if (hidden) PasswordVisualTransformation() else VisualTransformation.None,
        trailingIcon = if (!isPassword) null else {
            {
                IconButton(
                    onClick = { revealed = !revealed },
                    enabled = enabled,
                    modifier = Modifier.semantics {
                        contentDescription = if (revealed) "Hide $label" else "Show $label"
                    }
                ) {
                    Icon(
                        if (revealed) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                        contentDescription = null,
                        tint = Muted,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        },
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Accent,
            unfocusedBorderColor = Muted.copy(alpha = 0.4f),
            focusedLabelColor = Accent,
            cursorColor = Accent
        )
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountSheet(
    controller: CloudController,
    onDismiss: () -> Unit,
    onSyncNow: () -> Unit,
    onSignOut: () -> Unit
) {
    val user = controller.user ?: return

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Paper) {
        Column(
            Modifier.padding(horizontal = 24.dp).padding(bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(user.displayName, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1.1).sp, color = Ink)
            Text(user.email, color = Muted, fontSize = 13.sp)
            // Career totals come from the account and from nowhere else. A
            // guest round played on this device before signing in is not part
            // of this account's history.
            Text(
                "Best %,d · %,d rounds · highest tile %,d".format(user.bestScore, user.gamesPlayed, user.highestTile),
                color = Ink,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold
            )
            Text(controller.status, color = Muted, fontSize = 12.5.sp, lineHeight = 17.sp)
            Spacer(Modifier.height(4.dp))
            val syncing = controller.activity == CloudController.Activity.SYNCING
            Button(
                onClick = onSyncNow,
                enabled = !syncing,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Ink)
            ) {
                if (syncing) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                    Spacer(Modifier.width(10.dp))
                    Text("Syncing…", fontWeight = FontWeight.Bold)
                } else {
                    Text("Sync now", fontWeight = FontWeight.Bold)
                }
            }
            Text(
                "Signing out brings back the round this device was playing before you signed in. Your account keeps its own.",
                color = Muted,
                fontSize = 11.5.sp,
                lineHeight = 16.sp
            )
            val signingOut = controller.activity == CloudController.Activity.SIGNING_OUT
            TextButton(onClick = onSignOut, enabled = !signingOut, modifier = Modifier.fillMaxWidth()) {
                if (signingOut) {
                    CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = Muted)
                    Spacer(Modifier.width(8.dp))
                    Text("Signing out…", color = Muted)
                } else {
                    Text("Sign out", color = Muted)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeaderboardSheet(controller: CloudController, onDismiss: () -> Unit, onPeriod: (String) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Paper) {
        Column(
            Modifier.padding(horizontal = 24.dp).padding(bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Leaderboard", fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1.1).sp, color = Ink)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val loading = controller.activity == CloudController.Activity.LOADING_LEADERBOARD
                for ((key, label) in listOf("daily" to "Today", "weekly" to "This week", "all" to "All time")) {
                    val active = controller.leaderboardPeriod == key
                    Button(
                        onClick = { onPeriod(key) },
                        enabled = !loading,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (active) Ink else Color.White.copy(alpha = 0.7f),
                            contentColor = if (active) Color.White else Muted
                        ),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp)
                    ) { Text(label, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold) }
                }
            }

            if (controller.activity == CloudController.Activity.LOADING_LEADERBOARD && controller.leaderboard == null) {
                CircularProgressIndicator(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(vertical = 16.dp)
                        .size(28.dp),
                    strokeWidth = 3.dp,
                    color = Ink
                )
            }

            controller.leaderboard?.entries?.forEach { entry ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (entry.isViewer) Accent.copy(alpha = 0.14f) else Color.Transparent)
                        .padding(horizontal = 10.dp, vertical = 9.dp)
                        .semantics { contentDescription = "Rank ${entry.rank}, ${entry.displayName}, ${entry.score} points" },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("#${entry.rank}", color = Muted, fontFamily = FontFamily.Monospace, fontSize = 13.sp, modifier = Modifier.width(38.dp))
                    Text(entry.displayName, color = Ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.weight(1f))
                    Text("%,d".format(entry.highestTile), color = Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                    Spacer(Modifier.width(10.dp))
                    Text("%,d".format(entry.score), color = Ink, fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                }
            }

            Text(controller.leaderboardNote, color = Muted, fontSize = 12.5.sp)
        }
    }
}

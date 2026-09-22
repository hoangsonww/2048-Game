package com.sonnguyenhoang.game2048.cloud

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The account surface's state machine.
 *
 * Both runners are synchronous here, so a request and the state write that
 * follows it happen inside the call. That is what makes the ordering — and
 * every failure path — assertable without a device, an emulator, or a clock.
 */
class CloudControllerTest {

    private class FakePreferences(override var promptDismissed: Boolean = false, private var tokens: Boolean = false) : CloudPreferences {
        override val hasTokens: Boolean get() = tokens
        override var knownRevision: Int? = null
        fun withTokens() = apply { tokens = true }
    }

    private val board = listOf(512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0)
    private fun save(score: Int = 5600) = CloudSave(board, score, score, won = false, gameOver = false, moves = 400)

    /**
     * The seam is the transport underneath `CloudApi` rather than the API
     * itself: keeping the real client in the loop means these tests also
     * prove the controller and the wire format agree.
     */
    private class ScriptedTransport(private val routes: Map<String, HttpResponse>) : HttpTransport {
        val calls = mutableListOf<String>()
        /** The last request body sent to each route, so payloads are assertable. */
        val bodies = mutableMapOf<String, String?>()
        var failWith: CloudException? = null

        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
            val path = url.substringAfter("https://api.test").substringBefore("?")
            calls += "$method $path"
            bodies["$method $path"] = body
            failWith?.let { throw it }
            return routes[path] ?: HttpResponse(200, "{}")
        }
    }

    private fun controller(
        transport: ScriptedTransport,
        preferences: FakePreferences = FakePreferences(),
        tokens: CloudTokens? = null
    ): Pair<CloudController, MutableList<CloudSave>> {
        val store = object : TokenStore {
            private var value = tokens
            override fun read(): CloudTokens? = value
            override fun write(next: CloudTokens?) { value = next }
        }
        val applied = mutableListOf<CloudSave>()
        val api = CloudApi(transport, store, baseUrl = "https://api.test")
        val controller = CloudController(
            api = api,
            preferences = preferences,
            background = { it() },
            main = { it() }
        )
        return controller to applied
    }

    private val sessionBody = """
        {"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{"bestScore":900,"gamesPlayed":12,"highestTile":256}},
         "accessToken":"a","refreshToken":"r"}
    """.trimIndent()

    @Test
    fun `a fresh controller is signed out and invites the player`() {
        val (controller, _) = controller(ScriptedTransport(emptyMap()))

        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertFalse(controller.isSignedIn)
        assertTrue("an account is offered, never required", controller.showGuestPrompt)
        assertTrue(controller.status.contains("saved locally"))
    }

    @Test
    fun `dismissing the invitation hides it and remembers the choice`() {
        val preferences = FakePreferences()
        val (controller, _) = controller(ScriptedTransport(emptyMap()), preferences)

        controller.dismissPrompt()

        assertFalse(controller.showGuestPrompt)
        assertTrue(preferences.promptDismissed)
    }

    @Test
    fun `an invitation already dismissed on this device stays dismissed`() {
        val (controller, _) = controller(ScriptedTransport(emptyMap()), FakePreferences(promptDismissed = true))
        assertFalse(controller.showGuestPrompt)
    }

    @Test
    fun `registering signs in without touching the network again`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/register" to HttpResponse(201, sessionBody)))
        val (controller, _) = controller(transport)

        controller.register("ada", "ada@example.test", "Password1")

        assertEquals(CloudController.Phase.SIGNED_IN, controller.phase)
        assertEquals(CloudController.Activity.IDLE, controller.activity)
        assertFalse(controller.isBusy)
        assertEquals("Ada", controller.user?.displayName)
        assertFalse("signing in dismisses the invitation", controller.showGuestPrompt)
        // Authentication no longer decides what happens to the round. The game
        // does, because only the game knows which profile is now active.
        assertEquals(listOf("POST /api/v1/auth/register"), transport.calls)
    }

    @Test
    fun `adopting an account offers the server nothing`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/register" to HttpResponse(201, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"in_sync","save":null}"""),
                "/api/v1/auth/me" to HttpResponse(200, """{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"a@b.test","statistics":{"bestScore":0,"gamesPlayed":0,"highestTile":0}}}""")
            )
        )
        val (controller, applied) = controller(transport)

        var adopted = 0
        controller.register("ada", "ada@example.test", "Password1")
        controller.adoptAccountRound(applySave = { applied += it }, onAdopted = { adopted += 1 })

        assertEquals("the caller is told exactly once when the round has landed", 1, adopted)
        assertEquals(SyncResolution.IN_SYNC, controller.lastResolution)
        assertEquals("Signed in. Your account is ready.", controller.status)
        assertTrue("an account with no round leaves the clean board alone", applied.isEmpty())
        val sent = requireNotNull(transport.bodies["POST /api/v1/saves/sync"])
        assertTrue("the guest round is never offered to the account", sent.contains(""""save":null"""))
    }

    @Test
    fun `adopting an account survives a profile read that fails`() {
        // The round is what the player is waiting for; career totals can wait
        // for the next refresh.
        val transport = object : HttpTransport {
            val calls = mutableListOf<String>()
            override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
                val path = url.substringAfter("https://api.test").substringBefore("?")
                calls += "$method $path"
                if (path == "/api/v1/auth/me" && calls.count { it.endsWith("/auth/me") } > 0 && method == "GET") {
                    throw CloudException("network", "Could not reach the 2048 cloud.")
                }
                return when (path) {
                    "/api/v1/auth/login" -> HttpResponse(200, sessionBody)
                    "/api/v1/saves/sync" -> HttpResponse(
                        200,
                        """{"resolution":"downloaded","save":{"board":[2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":4,"moves":1}}"""
                    )
                    else -> HttpResponse(200, "{}")
                }
            }
        }
        val store = object : TokenStore {
            private var value: CloudTokens? = null
            override fun read(): CloudTokens? = value
            override fun write(next: CloudTokens?) { value = next }
        }
        val preferences = FakePreferences()
        val controller = CloudController(
            CloudApi(transport, store, baseUrl = "https://api.test"),
            preferences,
            background = { it() },
            main = { it() }
        )
        val applied = mutableListOf<CloudSave>()

        controller.login("ada", "Password1")
        controller.adoptAccountRound(applySave = { applied += it })

        assertEquals(1, applied.size)
        assertEquals("Ada", controller.user?.displayName)
        // A save with no revision leaves the remembered one alone.
        assertNull(preferences.knownRevision)
    }

    @Test
    fun `adopting an account reports a failure rather than claiming success`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1")

        transport.failWith = CloudException("network", "Could not reach the 2048 cloud.")
        controller.adoptAccountRound(applySave = { applied += it })

        assertTrue(controller.status.contains("Could not reach"))
        assertTrue(applied.isEmpty())
        assertEquals(CloudController.Activity.IDLE, controller.activity)
    }

    @Test
    fun `adopting while signed out does nothing`() {
        val transport = ScriptedTransport(emptyMap())
        val (controller, applied) = controller(transport)

        controller.adoptAccountRound(applySave = { applied += it })

        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `a submitted round refreshes the account's career totals`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/scores" to HttpResponse(201, """{"statistics":{"bestScore":5600,"gamesPlayed":13,"highestTile":512}}"""),
                "/api/v1/auth/me" to HttpResponse(200, """{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"a@b.test","statistics":{"bestScore":5600,"gamesPlayed":13,"highestTile":512}}}""")
            )
        )
        val (controller, _) = controller(transport)
        controller.login("ada", "Password1")

        controller.submitRound(save(), durationSeconds = 90)

        assertTrue(transport.calls.contains("POST /api/v1/scores"))
        assertEquals(5600, controller.user?.bestScore)
        assertEquals(13, controller.user?.gamesPlayed)
        assertEquals(512, controller.user?.highestTile)
    }

    @Test
    fun `adopting an account downloads the round it already had`() {
        val remote = """{"resolution":"downloaded","save":{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"moves":3,"revision":7}}"""
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, remote)
            )
        )
        val preferences = FakePreferences()
        val (controller, applied) = controller(transport, preferences)

        controller.login("ada", "Password1")
        controller.adoptAccountRound(applySave = { applied += it })

        assertEquals(1, applied.size)
        assertEquals(40, applied[0].score)
        assertEquals(7, preferences.knownRevision)
        assertEquals("Restored the round from your account.", controller.status)
    }

    @Test
    fun `signing in discards a revision from an earlier session`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val preferences = FakePreferences()
        preferences.knownRevision = 12
        val (controller, _) = controller(transport, preferences)

        controller.login("ada", "Password1")

        assertNull("a stale revision would make the next upload claim a false ancestry", preferences.knownRevision)
    }

    @Test
    fun `career totals are never lifted from the local round`() {
        // The bug this guards: a brand-new account advertising a best score and
        // a highest tile taken from whatever board happened to be on the device.
        val emptyStats = """
            {"user":{"id":"u1","username":"ada","displayName":"Ada","email":"a@b.test","statistics":{"bestScore":0,"gamesPlayed":0,"highestTile":0}},
             "accessToken":"a","refreshToken":"r"}
        """.trimIndent()
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, emptyStats),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":{"board":[512,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":5600,"bestScore":5600,"revision":1}}""")
            )
        )
        val (controller, applied) = controller(transport)

        controller.login("ada", "Password1")
        controller.sync({ save() }, { applied += it })

        assertEquals(0, controller.user?.bestScore)
        assertEquals(0, controller.user?.gamesPlayed)
        assertEquals(0, controller.user?.highestTile)
    }

    @Test
    fun `a rejected sign-in reports the reason and stays signed out`() {
        val transport = ScriptedTransport(
            mapOf("/api/v1/auth/login" to HttpResponse(401, """{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}"""))
        )
        val (controller, applied) = controller(transport)

        controller.login("ada", "wrong")

        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertNull(controller.user)
        assertNotNull(controller.authError)
        assertTrue(controller.authError!!.contains("not correct"))
    }

    @Test
    fun `clearing the auth error resets the form`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(401, """{"error":{"code":"x","message":"nope"}}""")))
        val (controller, applied) = controller(transport)

        controller.login("ada", "wrong")
        controller.clearAuthError()

        assertNull(controller.authError)
    }

    @Test
    fun `a downloaded round replaces the board and an upload does not`() {
        val remote = """{"resolution":"downloaded","save":{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"moves":3}}"""
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, remote)
            )
        )
        val (controller, applied) = controller(transport)

        controller.login("ada", "Password1")
        controller.sync({ save() }, { applied += it })

        assertEquals(1, applied.size)
        assertEquals(40, applied[0].score)
        assertEquals("Restored the round from your account.", controller.status)
    }

    @Test
    fun `sync now prefers the local board`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":{"board":[],"score":1,"revision":5}}"""),
                "/api/v1/auth/me" to HttpResponse(200, """{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{"bestScore":5600,"gamesPlayed":12,"highestTile":512}}}""")
            )
        )
        val preferences = FakePreferences().withTokens()
        val (controller, applied) = controller(transport, preferences)
        controller.login("ada", "Password1")
        transport.calls.clear()

        controller.syncNow({ save() }, { applied += it })

        assertTrue(transport.calls.any { it == "POST /api/v1/saves/sync" })
        assertEquals(5, preferences.knownRevision)
        assertEquals(5600, controller.user?.bestScore)
    }

    @Test
    fun `a remote-winning conflict replaces the board`() {
        val remote = """{"resolution":"conflicted","winner":"remote","save":{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"moves":3,"revision":2}}"""
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, remote)
            )
        )
        val preferences = FakePreferences()
        val (controller, applied) = controller(transport, preferences)

        controller.login("ada", "Password1")
        controller.sync({ save() }, { applied += it })

        assertEquals(1, applied.size)
        assertEquals(40, applied[0].score)
        assertEquals(2, preferences.knownRevision)
    }

    @Test
    fun `resetting a password ends the session this device held`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/auth/reset-password" to HttpResponse(200, """{"reset":true,"sessionsRevoked":3}""")
            )
        )
        val preferences = FakePreferences()
        val (controller, _) = controller(transport, preferences)
        controller.login("ada", "Password1")
        preferences.knownRevision = 4

        var reset = 0
        controller.resetPassword("ada", "ada@example.test", "Recovered1") { reset += 1 }

        assertEquals(1, reset)
        // The server revoked every session, this one included.
        assertFalse(controller.isSignedIn)
        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertNull(preferences.knownRevision)
        assertTrue(controller.status.contains("Sign in with your new password"))
        assertEquals(CloudController.Activity.IDLE, controller.activity)
    }

    @Test
    fun `a rejected reset is reported and changes nothing`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/auth/reset-password" to HttpResponse(
                    401,
                    """{"error":{"code":"invalid_credentials","message":"That username and email do not match an account."}}"""
                )
            )
        )
        val (controller, _) = controller(transport)
        controller.login("ada", "Password1")

        var reset = 0
        controller.resetPassword("ada", "wrong@example.test", "Recovered1") { reset += 1 }

        assertEquals(0, reset)
        assertTrue(controller.authError!!.contains("do not match an account"))
        assertTrue("a refused reset must not sign anybody out", controller.isSignedIn)
        assertEquals(CloudController.Activity.IDLE, controller.activity)
    }

    @Test
    fun `a reset works without a session to begin with`() {
        // The player who needs this is the one who cannot sign in.
        val transport = ScriptedTransport(
            mapOf("/api/v1/auth/reset-password" to HttpResponse(200, """{"reset":true,"sessionsRevoked":0}"""))
        )
        val (controller, _) = controller(transport)

        var reset = 0
        controller.resetPassword("ada", "ada@example.test", "Recovered1") { reset += 1 }

        assertEquals(1, reset)
        assertEquals(listOf("POST /api/v1/auth/reset-password"), transport.calls)
    }

    @Test
    fun `signing out clears the known revision`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":{"revision":9}}""")
            )
        )
        val preferences = FakePreferences()
        val (controller, applied) = controller(transport, preferences)
        controller.login("ada", "Password1")
        controller.sync({ save() }, { applied += it })
        assertEquals(9, preferences.knownRevision)

        controller.signOut()

        assertNull(preferences.knownRevision)
    }

    @Test
    fun `an upload leaves the local board alone`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":{"board":[],"score":1}}""")
            )
        )
        val (controller, applied) = controller(transport)

        controller.login("ada", "Password1")
        controller.sync({ save() }, { applied += it })

        assertTrue("the device that sent the round is already showing it", applied.isEmpty())
    }

    @Test
    fun `a conflict is explained in the player's own words`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"conflicted","winner":"remote","conflictSlot":"conflict-1","save":null}""")
            )
        )
        val (controller, applied) = controller(transport)

        controller.login("ada", "Password1")
        controller.sync({ save() }, { applied += it })

        assertEquals(SyncResolution.CONFLICTED, controller.lastResolution)
        assertTrue(controller.status.contains("the further one was kept, and the other is safe"))
    }

    @Test
    fun `syncing while signed out does nothing`() {
        val transport = ScriptedTransport(emptyMap())
        val (controller, applied) = controller(transport)

        controller.sync({ save() }, { applied += it })

        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `a failed sync reports itself without losing the session`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1")

        transport.failWith = CloudException("network", "Could not reach the 2048 cloud.")
        controller.sync({ save() }, { applied += it })

        assertTrue(controller.isSignedIn)
        assertTrue(controller.status.contains("Could not reach"))
    }

    @Test
    fun `restoring with no stored token makes no request`() {
        val transport = ScriptedTransport(emptyMap())
        val (controller, applied) = controller(transport)

        var live: Boolean? = null
        controller.restore { live = it }

        assertEquals(false, live)
        assertFalse(controller.hasStoredSession)
        assertTrue(transport.calls.isEmpty())
        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
    }

    @Test
    fun `restoring re-establishes the session and leaves reconciling to the caller`() {
        val transport = ScriptedTransport(
            mapOf("/api/v1/auth/me" to HttpResponse(200, """{"user":{"username":"ada","displayName":"Ada","statistics":{"bestScore":900}}}"""))
        )
        val (controller, _) = controller(transport, FakePreferences().withTokens(), CloudTokens("a", "r"))
        assertTrue(controller.hasStoredSession)

        var live: Boolean? = null
        controller.restore { live = it }

        assertEquals(true, live)
        assertEquals(CloudController.Phase.SIGNED_IN, controller.phase)
        assertEquals("ada", controller.user?.username)
        // Which round may be offered depends on which profile the device
        // adopted, and only the game knows that.
        assertEquals(listOf("GET /api/v1/auth/me"), transport.calls)
    }

    @Test
    fun `an offline launch says so rather than claiming the session expired`() {
        val transport = ScriptedTransport(emptyMap())
        transport.failWith = CloudException("network", "Could not reach the 2048 cloud.")
        val (controller, applied) = controller(transport, FakePreferences().withTokens(), CloudTokens("a", "r"))

        var live: Boolean? = null
        controller.restore { live = it }

        assertEquals(false, live)
        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertTrue(controller.status.contains("Offline"))
        assertFalse("an offline launch is not an expiry", controller.status.contains("expired"))
    }

    @Test
    fun `signing out clears the session and reassures the player`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1")

        controller.signOut()

        assertFalse(controller.isSignedIn)
        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertNull(controller.lastResolution)
        assertTrue(controller.status.contains("own round is back"))
    }

    @Test
    fun `a scoreless round is never submitted`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1")
        transport.calls.clear()

        controller.submitRound(save(score = 0))

        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `a signed-out player's round is never submitted`() {
        val transport = ScriptedTransport(emptyMap())
        val (controller, _) = controller(transport)

        controller.submitRound(save())

        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `a failed submission is swallowed rather than shown as an error`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1")
        val statusBefore = controller.status

        transport.failWith = CloudException("network", "offline")
        controller.submitRound(save())

        // The score is already on the player's screen and in local storage.
        assertEquals(statusBefore, controller.status)
    }

    @Test
    fun `the leaderboard loads, reports its summary, and remembers the window`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/leaderboard" to HttpResponse(
                    200,
                    """{"entries":[{"rank":1,"username":"ada","displayName":"Ada","score":9000,"highestTile":2048,"isViewer":true}],"summary":{"players":3,"topScore":9000}}"""
                )
            )
        )
        val (controller, _) = controller(transport)

        controller.loadLeaderboard("weekly")

        assertEquals("weekly", controller.leaderboardPeriod)
        assertEquals(1, controller.leaderboard?.entries?.size)
        assertTrue(controller.leaderboardNote.contains("3 players"))
    }

    @Test
    fun `an empty window says so instead of showing nothing`() {
        val transport = ScriptedTransport(mapOf("/api/v1/leaderboard" to HttpResponse(200, """{"entries":[],"summary":{"players":0,"topScore":0}}""")))
        val (controller, _) = controller(transport)

        controller.loadLeaderboard()

        assertTrue(controller.leaderboardNote.contains("No rounds in this window yet"))
    }

    @Test
    fun `a failed leaderboard read shows the reason and clears stale rows`() {
        val transport = ScriptedTransport(emptyMap())
        transport.failWith = CloudException("network", "Could not reach the 2048 cloud.")
        val (controller, _) = controller(transport)

        controller.loadLeaderboard()

        assertNull(controller.leaderboard)
        assertTrue(controller.leaderboardNote.contains("Could not reach"))
    }

    @Test
    fun `an unexpected failure is still reported as something a player can read`() {
        val transport = object : HttpTransport {
            override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse =
                throw IllegalStateException("a bug, not a network problem")
        }
        val store = object : TokenStore {
            override fun read(): CloudTokens? = null
            override fun write(tokens: CloudTokens?) = Unit
        }
        val controller = CloudController(
            CloudApi(transport, store, baseUrl = "https://api.test"),
            FakePreferences(),
            background = { it() },
            main = { it() }
        )

        controller.loadLeaderboard()

        assertTrue(controller.leaderboardNote.contains("a bug, not a network problem"))
        assertEquals(CloudController.Activity.IDLE, controller.activity)
    }

    @Test
    fun `in-flight requests publish a busy activity until they finish`() {
        val queued = ArrayDeque<() -> Unit>()
        fun drain() { while (queued.isNotEmpty()) queued.removeFirst().invoke() }

        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":null}"""),
                "/api/v1/leaderboard" to HttpResponse(200, """{"entries":[],"summary":{"players":0,"topScore":0}}""")
            )
        )
        val store = object : TokenStore {
            private var value: CloudTokens? = null
            override fun read(): CloudTokens? = value
            override fun write(tokens: CloudTokens?) { value = tokens }
        }
        val controller = CloudController(
            CloudApi(transport, store, baseUrl = "https://api.test"),
            FakePreferences(),
            background = { queued.add(it) },
            main = { it() }
        )

        controller.login("ada", "Password1")
        assertEquals(CloudController.Activity.AUTHENTICATING, controller.activity)
        assertTrue(controller.isBusy)
        assertTrue(controller.status.contains("Signing in"))
        drain()
        assertEquals(CloudController.Activity.IDLE, controller.activity)
        assertEquals(CloudController.Phase.SIGNED_IN, controller.phase)

        controller.syncNow({ save() }, {})
        assertEquals(CloudController.Activity.SYNCING, controller.activity)
        assertTrue(controller.status.contains("Syncing"))
        drain()
        assertEquals(CloudController.Activity.IDLE, controller.activity)

        controller.loadLeaderboard()
        assertEquals(CloudController.Activity.LOADING_LEADERBOARD, controller.activity)
        assertEquals("Loading…", controller.leaderboardNote)
        drain()
        assertEquals(CloudController.Activity.IDLE, controller.activity)
    }
}

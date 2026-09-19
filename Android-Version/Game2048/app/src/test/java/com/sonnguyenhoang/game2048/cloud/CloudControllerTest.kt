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
        var failWith: CloudException? = null

        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
            val path = url.substringAfter("https://api.test").substringBefore("?")
            calls += "$method $path"
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
    fun `registering signs in and reconciles immediately`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/register" to HttpResponse(201, sessionBody),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":null}""")
            )
        )
        val (controller, applied) = controller(transport)

        controller.register("ada", "ada@example.test", "Password1", { save() }, { applied += it })

        assertEquals(CloudController.Phase.SIGNED_IN, controller.phase)
        assertEquals("Ada", controller.user?.displayName)
        assertFalse("signing in dismisses the invitation", controller.showGuestPrompt)
        assertEquals(SyncResolution.UPLOADED, controller.lastResolution)
        assertEquals("Round saved to your account.", controller.status)
        assertEquals(listOf("POST /api/v1/auth/register", "POST /api/v1/saves/sync"), transport.calls)
    }

    @Test
    fun `a rejected sign-in reports the reason and stays signed out`() {
        val transport = ScriptedTransport(
            mapOf("/api/v1/auth/login" to HttpResponse(401, """{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}"""))
        )
        val (controller, applied) = controller(transport)

        controller.login("ada", "wrong", { save() }, { applied += it })

        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertNull(controller.user)
        assertNotNull(controller.authError)
        assertTrue(controller.authError!!.contains("not correct"))
    }

    @Test
    fun `clearing the auth error resets the form`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(401, """{"error":{"code":"x","message":"nope"}}""")))
        val (controller, applied) = controller(transport)

        controller.login("ada", "wrong", { save() }, { applied += it })
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

        controller.login("ada", "Password1", { save() }, { applied += it })

        assertEquals(1, applied.size)
        assertEquals(40, applied[0].score)
        assertEquals("Restored the round from your account.", controller.status)
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

        controller.login("ada", "Password1", { save() }, { applied += it })

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

        controller.login("ada", "Password1", { save() }, { applied += it })

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
        controller.login("ada", "Password1", { save() }, { applied += it })

        transport.failWith = CloudException("network", "Could not reach the 2048 cloud.")
        controller.sync({ save() }, { applied += it })

        assertTrue(controller.isSignedIn)
        assertTrue(controller.status.contains("Could not reach"))
    }

    @Test
    fun `restoring with no stored token makes no request`() {
        val transport = ScriptedTransport(emptyMap())
        val (controller, applied) = controller(transport)

        controller.restore({ save() }, { applied += it })

        assertTrue(transport.calls.isEmpty())
        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
    }

    @Test
    fun `restoring re-establishes the session and reconciles`() {
        val transport = ScriptedTransport(
            mapOf(
                "/api/v1/auth/me" to HttpResponse(200, """{"user":{"username":"ada","displayName":"Ada","statistics":{"bestScore":900}}}"""),
                "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"in_sync","save":null}""")
            )
        )
        val (controller, applied) = controller(transport, FakePreferences().withTokens(), CloudTokens("a", "r"))

        controller.restore({ save() }, { applied += it })

        assertEquals(CloudController.Phase.SIGNED_IN, controller.phase)
        assertEquals("ada", controller.user?.username)
        assertEquals("Everything is in sync.", controller.status)
    }

    @Test
    fun `an offline launch says so rather than claiming the session expired`() {
        val transport = ScriptedTransport(emptyMap())
        transport.failWith = CloudException("network", "Could not reach the 2048 cloud.")
        val (controller, applied) = controller(transport, FakePreferences().withTokens(), CloudTokens("a", "r"))

        controller.restore({ save() }, { applied += it })

        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertTrue(controller.status.contains("Offline"))
        assertFalse("an offline launch is not an expiry", controller.status.contains("expired"))
    }

    @Test
    fun `signing out clears the session and reassures the player`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1", { save() }, { applied += it })

        controller.signOut()

        assertFalse(controller.isSignedIn)
        assertEquals(CloudController.Phase.SIGNED_OUT, controller.phase)
        assertNull(controller.lastResolution)
        assertTrue(controller.status.contains("stays on this device"))
    }

    @Test
    fun `a scoreless round is never submitted`() {
        val transport = ScriptedTransport(mapOf("/api/v1/auth/login" to HttpResponse(200, sessionBody)))
        val (controller, applied) = controller(transport)
        controller.login("ada", "Password1", { save() }, { applied += it })
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
        controller.login("ada", "Password1", { save() }, { applied += it })
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
    }
}

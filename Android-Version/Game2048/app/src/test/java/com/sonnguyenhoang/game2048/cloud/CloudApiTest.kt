package com.sonnguyenhoang.game2048.cloud

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The cloud client, driven through a fake transport.
 *
 * The interesting cases are the ones a device makes hard to produce on
 * demand — an expired token, a dropped connection, a malformed response — so
 * they are all here rather than in the instrumentation suite.
 */
class CloudApiTest {

    private data class Call(val method: String, val url: String, val headers: Map<String, String>, val body: String?)

    private class FakeTransport(vararg responses: HttpResponse) : HttpTransport {
        val calls = mutableListOf<Call>()
        private val queue = ArrayDeque(responses.toList())
        var throwNetworkError = false

        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
            calls += Call(method, url, headers, body)
            if (throwNetworkError) {
                throw CloudException("network", "Could not reach the 2048 cloud. Your game is still saved on this device.")
            }
            return queue.removeFirstOrNull() ?: error("No queued response for $method $url")
        }
    }

    private class MemoryTokenStore(private var tokens: CloudTokens? = null) : TokenStore {
        var writes = 0
        override fun read(): CloudTokens? = tokens
        override fun write(value: CloudTokens?) {
            tokens = value
            writes += 1
        }
    }

    private val sessionBody = """
        {
          "user": {
            "id": "u1",
            "username": "ada",
            "displayName": "Ada",
            "email": "ada@example.test",
            "statistics": { "bestScore": 900, "gamesPlayed": 12, "highestTile": 256 }
          },
          "accessToken": "access-1",
          "refreshToken": "refresh-1"
        }
    """.trimIndent()

    private val board = listOf(512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0)
    private fun save(score: Int = 5600, moves: Int = 480, baseRevision: Int? = null) =
        CloudSave(board, score, score, won = false, gameOver = false, moves = moves, baseRevision = baseRevision)

    private fun api(transport: HttpTransport, store: TokenStore = MemoryTokenStore()) =
        CloudApi(transport, store, baseUrl = "https://api.test", deviceId = "pixel-test")

    @Test
    fun `registering stores the tokens and returns the account`() {
        val transport = FakeTransport(HttpResponse(201, sessionBody))
        val store = MemoryTokenStore()

        val session = api(transport, store).register("ada", "ada@example.test", "Password1")

        assertEquals("ada", session.user.username)
        assertEquals("Ada", session.user.displayName)
        assertEquals(900, session.user.bestScore)
        assertEquals("access-1", store.read()?.accessToken)
        assertEquals("POST", transport.calls[0].method)
        assertEquals("https://api.test/api/v1/auth/register", transport.calls[0].url)
        assertEquals("android", JSONObject(transport.calls[0].body!!).getString("client"))
    }

    @Test
    fun `whitespace a player typed is trimmed before it becomes their username`() {
        val transport = FakeTransport(HttpResponse(201, sessionBody))
        api(transport).register("  ada  ", "  ada@example.test ", "Password1")

        val body = JSONObject(transport.calls[0].body!!)
        assertEquals("ada", body.getString("username"))
        assertEquals("ada@example.test", body.getString("email"))
    }

    @Test
    fun `a player with no display name is shown by username`() {
        val transport = FakeTransport(HttpResponse(200, """{"user":{"username":"bob","displayName":""},"accessToken":"a","refreshToken":"r"}"""))
        val session = api(transport).login("bob", "Password1")
        assertEquals("bob", session.user.displayName)
    }

    @Test
    fun `a rejected sign-in surfaces the server's code and message`() {
        val transport = FakeTransport(
            HttpResponse(401, """{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}""")
        )

        val error = assertThrows(CloudException::class.java) { api(transport).login("ada", "wrong") }

        assertEquals("invalid_credentials", error.code)
        assertEquals(401, error.status)
        assertTrue(error.message.contains("not correct"))
    }

    @Test
    fun `an error response with no parsable body still produces a usable error`() {
        val transport = FakeTransport(HttpResponse(502, "<html>bad gateway</html>"))

        val error = assertThrows(CloudException::class.java) { api(transport).login("ada", "x") }

        assertEquals("http_error", error.code)
        assertTrue(error.message.contains("502"))
    }

    @Test
    fun `a dropped connection is reported as a network failure, not a crash`() {
        val transport = FakeTransport().apply { throwNetworkError = true }

        val error = assertThrows(CloudException::class.java) { api(transport).login("ada", "x") }

        assertTrue(error.isNetworkFailure)
        assertTrue("the message should reassure, not alarm", error.message.contains("still saved on this device"))
    }

    @Test
    fun `an authenticated call without a session fails before touching the network`() {
        val transport = FakeTransport()
        val error = assertThrows(CloudException::class.java) { api(transport).sync(save()) }

        assertEquals(401, error.status)
        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `an expired access token is refreshed once and the request retried`() {
        val transport = FakeTransport(
            HttpResponse(401, """{"error":{"code":"unauthorized","message":"expired"}}"""),
            HttpResponse(200, """{"accessToken":"access-2","refreshToken":"refresh-2","user":{"username":"ada"}}"""),
            HttpResponse(200, """{"resolution":"uploaded","save":{"board":[],"score":10,"revision":3}}""")
        )
        val store = MemoryTokenStore(CloudTokens("stale", "refresh-1"))

        val result = api(transport, store).sync(save())

        assertEquals(SyncResolution.UPLOADED, result.resolution)
        assertEquals(3, transport.calls.size)
        assertEquals("https://api.test/api/v1/auth/refresh", transport.calls[1].url)
        assertEquals("Bearer access-2", transport.calls[2].headers["Authorization"])
        assertEquals("access-2", store.read()?.accessToken)
    }

    @Test
    fun `a rejected refresh signs the player out rather than looping`() {
        val transport = FakeTransport(
            HttpResponse(401, """{"error":{"code":"unauthorized","message":"expired"}}"""),
            HttpResponse(401, """{"error":{"code":"unauthorized","message":"that session is gone"}}""")
        )
        val store = MemoryTokenStore(CloudTokens("stale", "dead"))

        assertThrows(CloudException::class.java) { api(transport, store).sync(save()) }

        assertNull("an unusable session must be discarded", store.read())
        assertEquals(2, transport.calls.size)
    }

    @Test
    fun `a dropped connection during refresh does not sign the player out`() {
        // Someone on a train has not been signed out; they are simply offline.
        val transport = object : HttpTransport {
            var seen = 0
            override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
                seen += 1
                if (seen == 1) return HttpResponse(401, """{"error":{"code":"unauthorized","message":"expired"}}""")
                throw CloudException("network", "Could not reach the 2048 cloud.")
            }
        }
        val store = MemoryTokenStore(CloudTokens("stale", "refresh-1"))

        assertThrows(CloudException::class.java) { api(transport, store).sync(save()) }

        assertNotNull("the tokens must survive a failed reachability check", store.read())
    }

    @Test
    fun `refreshing with a half-written token entry fails cleanly`() {
        val transport = FakeTransport(HttpResponse(401, """{"error":{"code":"unauthorized","message":"expired"}}"""))
        val store = MemoryTokenStore(CloudTokens("access", ""))

        val error = assertThrows(CloudException::class.java) { api(transport, store).sync(save()) }

        assertEquals(401, error.status)
        assertNull(store.read())
    }

    @Test
    fun `a sync sends the board flat with the client and device attached`() {
        val transport = FakeTransport(HttpResponse(200, """{"resolution":"in_sync","save":null}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        api(transport, store).sync(save(baseRevision = 4))

        val body = JSONObject(transport.calls[0].body!!)
        assertEquals("current", body.getString("slot"))
        assertEquals("auto", body.getString("strategy"))
        val sent = body.getJSONObject("save")
        assertEquals(16, sent.getJSONArray("board").length())
        assertEquals(512, sent.getJSONArray("board").getInt(0))
        assertEquals("android", sent.getString("client"))
        assertEquals("pixel-test", sent.getString("deviceId"))
        assertEquals(4, sent.getInt("baseRevision"))
    }

    @Test
    fun `a sync with no local save sends null rather than an empty board`() {
        val transport = FakeTransport(HttpResponse(200, """{"resolution":"downloaded","save":null}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        api(transport, store).sync(null)

        assertTrue(JSONObject(transport.calls[0].body!!).isNull("save"))
    }

    @Test
    fun `a save without a baseRevision omits the field entirely`() {
        val transport = FakeTransport(HttpResponse(200, """{"resolution":"uploaded","save":null}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        api(transport, store).sync(save())

        assertFalse(JSONObject(transport.calls[0].body!!).getJSONObject("save").has("baseRevision"))
    }

    @Test
    fun `a conflict reports the winner and the slot the other round was kept in`() {
        val transport = FakeTransport(
            HttpResponse(200, """{"resolution":"conflicted","winner":"remote","conflictSlot":"conflict-abc","save":{"board":[2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":4,"moves":1,"revision":7}}""")
        )
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        val result = api(transport, store).sync(save())

        assertEquals(SyncResolution.CONFLICTED, result.resolution)
        assertEquals("remote", result.winner)
        assertEquals("conflict-abc", result.conflictSlot)
        assertEquals(16, result.save?.board?.size)
        assertEquals(7, result.save?.revision)
    }

    @Test
    fun `an unfamiliar resolution is treated as in sync rather than crashing`() {
        // A server that grows a new resolution must not break an old build.
        val transport = FakeTransport(HttpResponse(200, """{"resolution":"something-new","save":null}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        assertEquals(SyncResolution.IN_SYNC, api(transport, store).sync(save()).resolution)
    }

    @Test
    fun `submitting a score sends the round the player finished`() {
        val transport = FakeTransport(HttpResponse(201, """{"score":{"id":"s1"},"duplicate":false}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        api(transport, store).submitScore(save(), durationSeconds = 540)

        val body = JSONObject(transport.calls[0].body!!)
        assertEquals(5600, body.getInt("score"))
        assertEquals(480, body.getInt("moves"))
        assertEquals(540, body.getInt("durationSeconds"))
        assertEquals("android", body.getString("client"))
    }

    @Test
    fun `the leaderboard is readable without signing in`() {
        val transport = FakeTransport(
            HttpResponse(200, """{"entries":[{"rank":1,"username":"ada","displayName":"Ada","score":9000,"highestTile":2048,"isViewer":false}],"summary":{"players":1,"topScore":9000}}""")
        )

        val page = api(transport).leaderboard("weekly", 5)

        assertNull("a signed-out read carries no token", transport.calls[0].headers["Authorization"])
        assertTrue(transport.calls[0].url.endsWith("period=weekly&limit=5&offset=0"))
        assertEquals(1, page.entries.size)
        assertEquals("Ada", page.entries[0].displayName)
        assertEquals(9000, page.topScore)
    }

    @Test
    fun `the leaderboard is authenticated once the player signs in`() {
        val transport = FakeTransport(HttpResponse(200, """{"entries":[],"summary":{}}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        api(transport, store).leaderboard()

        assertEquals("Bearer access-1", transport.calls[0].headers["Authorization"])
    }

    @Test
    fun `an empty leaderboard payload yields an empty page rather than an error`() {
        val transport = FakeTransport(HttpResponse(200, "{}"))
        val page = api(transport).leaderboard()

        assertTrue(page.entries.isEmpty())
        assertEquals(0, page.players)
    }

    @Test
    fun `currentUser returns null when there is nothing stored`() {
        val transport = FakeTransport()
        assertNull(api(transport).currentUser())
        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `currentUser reads the account behind a stored token`() {
        val transport = FakeTransport(HttpResponse(200, """{"user":{"username":"ada","displayName":"Ada","statistics":{"bestScore":42}}}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        val user = api(transport, store).currentUser()

        assertEquals("ada", user?.username)
        assertEquals(42, user?.bestScore)
    }

    @Test
    fun `signing out clears the session even when the revoke call fails`() {
        val transport = FakeTransport().apply { throwNetworkError = true }
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        api(transport, store).logout()

        assertNull("the player asked to be signed out; a failed revoke does not change that", store.read())
    }

    @Test
    fun `signing out with nothing stored makes no request`() {
        val transport = FakeTransport()
        api(transport).logout()
        assertTrue(transport.calls.isEmpty())
    }

    @Test
    fun `a trailing slash on the base URL does not produce a double slash`() {
        val transport = FakeTransport(HttpResponse(200, "{}"))
        CloudApi(transport, MemoryTokenStore(), baseUrl = "https://api.test///").leaderboard()

        assertTrue(transport.calls[0].url.startsWith("https://api.test/api/v1/"))
    }

    @Test
    fun `every request identifies itself as the Android client`() {
        val transport = FakeTransport(HttpResponse(200, "{}"))
        api(transport).leaderboard()
        assertEquals("android", transport.calls[0].headers["X-Client"])
    }

    @Test
    fun `a success with an empty body is not an error`() {
        val transport = FakeTransport(HttpResponse(204, ""))
        val page = api(transport).leaderboard()
        assertTrue(page.entries.isEmpty())
    }

    @Test
    fun `an error envelope with blank fields still reads sensibly`() {
        val transport = FakeTransport(HttpResponse(400, """{"error":{"code":"","message":""}}"""))

        val error = assertThrows(CloudException::class.java) { api(transport).login("ada", "x") }

        assertEquals("http_error", error.code)
        assertTrue(error.message.contains("400"))
    }

    @Test
    fun `a JSON null for the conflict fields reads as absent`() {
        // `optString` turns a JSON null into the literal text "null", which
        // would otherwise be shown to a player as a slot name.
        val transport = FakeTransport(HttpResponse(200, """{"resolution":"uploaded","winner":null,"conflictSlot":null,"save":null}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        val result = api(transport, store).sync(save())

        assertNull(result.winner)
        assertNull(result.conflictSlot)
        assertNull(result.save)
    }

    @Test
    fun `a save payload with no board yields an empty board rather than throwing`() {
        val transport = FakeTransport(HttpResponse(200, """{"resolution":"downloaded","save":{"score":10}}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        val result = api(transport, store).sync(null)

        assertEquals(emptyList<Int>(), result.save?.board)
        assertEquals(10, result.save?.score)
    }

    @Test
    fun `a response with no user object does not crash the caller`() {
        val transport = FakeTransport(HttpResponse(200, "{}"))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        val user = api(transport, store).currentUser()

        assertEquals("", user?.username)
        assertEquals(0, user?.bestScore)
    }

    @Test
    fun `every sync resolution the server can send maps to a known value`() {
        assertEquals(SyncResolution.UPLOADED, SyncResolution.from("uploaded"))
        assertEquals(SyncResolution.DOWNLOADED, SyncResolution.from("downloaded"))
        assertEquals(SyncResolution.CONFLICTED, SyncResolution.from("conflicted"))
        assertEquals(SyncResolution.IN_SYNC, SyncResolution.from("in_sync"))
        assertEquals(SyncResolution.IN_SYNC, SyncResolution.from(null))
    }

    @Test
    fun `a non-401 failure is not retried`() {
        val transport = FakeTransport(HttpResponse(500, """{"error":{"code":"internal_error","message":"boom"}}"""))
        val store = MemoryTokenStore(CloudTokens("access-1", "refresh-1"))

        assertThrows(CloudException::class.java) { api(transport, store).sync(save()) }

        assertEquals("a server error is the server's problem, not a stale token", 1, transport.calls.size)
    }
}

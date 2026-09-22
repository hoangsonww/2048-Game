package com.sonnguyenhoang.game2048.cloud

import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * The one place this app touches the network.
 *
 * It is an interface with a single method so `CloudApi` — which holds every
 * decision worth testing: what to send, how to read a response, when to
 * refresh a token — can be driven entirely from a JVM unit test with a fake.
 * The real implementation below is the only part that needs a device, and the
 * coverage gate excludes it for exactly that reason.
 */
data class HttpResponse(val status: Int, val body: String)

interface HttpTransport {
    /**
     * @throws CloudException with code `network` when the request never
     * reached the server. A non-2xx response is *not* an exception: it is a
     * result the caller inspects, because the API's error envelope is part of
     * its contract.
     */
    fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse
}

/**
 * `HttpURLConnection` rather than OkHttp or Retrofit.
 *
 * The client makes a handful of small JSON requests. A networking stack, a
 * converter, and a code generator would add three dependencies, a build-time
 * step, and roughly a megabyte to an APK whose entire point is that it is a
 * self-contained offline game.
 */
class UrlConnectionTransport(
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 15_000
) : HttpTransport {

    override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = connectTimeoutMs
                readTimeout = readTimeoutMs
                headers.forEach { (name, value) -> setRequestProperty(name, value) }
                if (body != null) {
                    doOutput = true
                    outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
            }

            val status = connection.responseCode
            // An error response still carries the JSON envelope the caller
            // needs, and it arrives on `errorStream` rather than `inputStream`.
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use(BufferedReader::readText).orEmpty()
            return HttpResponse(status, text)
        } catch (error: Exception) {
            throw CloudException("network", "Could not reach the 2048 cloud. Your game is still saved on this device.")
        } finally {
            connection?.disconnect()
        }
    }
}

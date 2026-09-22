package com.sonnguyenhoang.game2048

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Short procedural cues for the Android client.
 *
 * Generated PCM — no raw assets in the APK, and mute is a single preference
 * flip. Failures are swallowed: a broken audio path must never take the board
 * down with it.
 *
 * The shape here is a **mixer**, not a queue, and that is the whole point.
 * Allocating an `AudioTrack` per cue costs tens of milliseconds and a thread
 * each time, so a fast run of moves produced a growing backlog that arrived
 * long after the moves that caused it. Instead one streaming track stays open
 * and a writer thread sums the currently sounding voices into it. A cue is
 * therefore audible within one buffer of being asked for, several can overlap,
 * and a player who outruns the mixer loses the oldest voice rather than
 * hearing the whole backlog later.
 */
class GameSounds(
    private val preferences: android.content.SharedPreferences,
    private val sink: ToneSink = AudioTrackSink(SAMPLE_RATE, CHUNK_FRAMES),
    private val idleReleaseMs: Long = IDLE_RELEASE_MS
) {
    private val key = "game2048_sound_enabled_v1"

    /** Where mixed samples go. Separated so the mixer is testable off-device. */
    interface ToneSink {
        /** Opens the device. Returns false if audio is unavailable. */
        fun start(): Boolean

        /** Blocking write of [frames] samples, which also paces the mixer. */
        fun write(buffer: ShortArray, frames: Int)

        /** Releases the device until the next [start]. */
        fun stop()
    }

    /** One sounding cue. */
    private class Voice(
        val frequency: Double,
        val slideTo: Double?,
        val volume: Double,
        val totalFrames: Int,
        var delayFrames: Int
    ) {
        var position = 0
        val finished: Boolean get() = position >= totalFrames
    }

    private val lock = Object()
    private val voices = ArrayList<Voice>(MAX_VOICES)
    private val chunk = ShortArray(CHUNK_FRAMES)
    private val mix = DoubleArray(CHUNK_FRAMES)
    private var writer: Thread? = null
    private var running = false
    private var cached = preferences.getBoolean(key, true)

    var isEnabled: Boolean
        get() = cached
        set(value) {
            cached = value
            preferences.edit().putBoolean(key, value).apply()
            if (!value) synchronized(lock) { voices.clear() }
        }

    fun toggle(): Boolean {
        isEnabled = !isEnabled
        return isEnabled
    }

    fun move() = blip(420.0, 0.05, 0.22)
    fun merge(points: Int = 4) {
        val base = 520.0 + min(400.0, log2(max(4, points).toDouble()) * 55.0)
        blip(base, 0.09, 0.32)
        blip(base * 1.5, 0.07, 0.16, delaySec = 0.02)
    }
    fun undo() = blip(360.0, 0.07, 0.24, slideTo = 240.0)
    fun newGame() {
        blip(480.0, 0.06, 0.26)
        blip(640.0, 0.08, 0.2, delaySec = 0.07)
    }
    fun win() {
        listOf(523.0, 659.0, 784.0, 1046.0).forEachIndexed { index, frequency ->
            blip(frequency, 0.14, 0.3, delaySec = index * 0.09)
        }
    }
    fun gameOver() {
        blip(280.0, 0.18, 0.26, slideTo = 140.0)
        blip(180.0, 0.22, 0.18, delaySec = 0.1, slideTo = 90.0)
    }
    fun invalid() = blip(160.0, 0.04, 0.12)

    /** Stops the mixer thread and releases the device. Call from `onDispose`. */
    fun release() {
        val thread = synchronized(lock) {
            running = false
            voices.clear()
            lock.notifyAll()
            writer.also { writer = null }
        }
        thread?.join(500)
    }

    private fun blip(
        frequency: Double,
        durationSec: Double,
        volume: Double,
        delaySec: Double = 0.0,
        slideTo: Double? = null
    ) {
        if (!isEnabled) return
        val voice = Voice(
            frequency = frequency,
            slideTo = slideTo,
            volume = volume,
            totalFrames = max(1, (durationSec * SAMPLE_RATE).roundToInt()),
            delayFrames = max(0, (delaySec * SAMPLE_RATE).roundToInt())
        )
        synchronized(lock) {
            // Past the cap the oldest voice is cut off. Buffering instead is
            // exactly the backlog this class exists to avoid.
            if (voices.size >= MAX_VOICES) voices.removeAt(0)
            voices += voice
            lock.notifyAll()
        }
        ensureWriter()
    }

    private fun ensureWriter() {
        synchronized(lock) {
            if (running) return
            running = true
        }
        val thread = Thread({ pump() }, "game2048-sound")
        thread.isDaemon = true
        thread.priority = Thread.NORM_PRIORITY + 1
        synchronized(lock) { writer = thread }
        runCatching { thread.start() }.onFailure {
            synchronized(lock) {
                running = false
                writer = null
            }
        }
    }

    /**
     * Mixes and writes until the cues stop coming.
     *
     * With nothing sounding the loop waits on the lock rather than pushing
     * silence, and gives the device back after a short idle window: a puzzle
     * game has no business owning an audio device between moves. `write` is
     * blocking, so it — not a timer — is what paces the mixing.
     */
    private fun pump() {
        if (!runCatching { sink.start() }.getOrDefault(false)) {
            synchronized(lock) {
                running = false
                writer = null
            }
            return
        }
        try {
            while (true) {
                val mixed = synchronized(lock) {
                    if (!running) return@synchronized false
                    if (voices.isEmpty()) {
                        // A spurious wake-up that finds no work is treated as
                        // the idle timeout; the next cue simply starts the
                        // mixer again, which costs one track allocation.
                        runCatching { lock.wait(idleReleaseMs) }
                        if (!running || voices.isEmpty()) return@synchronized false
                    }
                    mixInto(chunk)
                    true
                }
                if (!mixed) break
                runCatching { sink.write(chunk, CHUNK_FRAMES) }.onFailure { return@pump }
            }
        } finally {
            runCatching { sink.stop() }
            synchronized(lock) {
                running = false
                writer = null
            }
        }
    }

    /** Sums the sounding voices into [out]. Caller holds [lock]. */
    private fun mixInto(out: ShortArray) {
        java.util.Arrays.fill(mix, 0.0)
        val iterator = voices.iterator()
        while (iterator.hasNext()) {
            val voice = iterator.next()
            for (index in 0 until CHUNK_FRAMES) {
                if (voice.delayFrames > 0) {
                    voice.delayFrames -= 1
                    continue
                }
                if (voice.finished) break
                val progress = voice.position.toDouble() / voice.totalFrames
                val frequency = if (voice.slideTo != null) {
                    voice.frequency + (voice.slideTo - voice.frequency) * progress
                } else {
                    voice.frequency
                }
                val t = voice.position.toDouble() / SAMPLE_RATE
                // Half a sine over the cue's length: fades in and out, so a
                // burst starting mid-buffer never clicks.
                val envelope = sin(min(1.0, progress * PI))
                mix[index] += sin(2.0 * PI * frequency * t) * voice.volume * envelope
                voice.position += 1
            }
            if (voice.finished) iterator.remove()
        }
        for (index in 0 until CHUNK_FRAMES) {
            val clamped = mix[index].coerceIn(-1.0, 1.0)
            out[index] = (clamped * Short.MAX_VALUE).toInt().toShort()
        }
    }

    /** The real device. Everything Android-specific about playback is here. */
    internal class AudioTrackSink(
        private val sampleRate: Int,
        private val chunkFrames: Int
    ) : ToneSink {
        private var track: AudioTrack? = null

        override fun start(): Boolean = runCatching {
            val minimum = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            // Two chunks of headroom keeps the write blocking (which is what
            // paces the mixer) without adding audible latency.
            val bytes = max(minimum, chunkFrames * 2 * 2)
            val built = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bytes)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            built.play()
            track = built
            true
        }.getOrDefault(false)

        override fun write(buffer: ShortArray, frames: Int) {
            track?.write(buffer, 0, frames)
        }

        override fun stop() {
            runCatching {
                track?.pause()
                track?.flush()
                track?.release()
            }
            track = null
        }
    }

    companion object {
        const val SAMPLE_RATE = 22_050

        /** ~11.6 ms of audio: short enough to be prompt, long enough to be cheap. */
        const val CHUNK_FRAMES = 256

        /** Cues sounding at once. Past this the oldest is cut off. */
        const val MAX_VOICES = 8

        /** How long the device stays open after the last cue ends. */
        const val IDLE_RELEASE_MS = 1_200L
    }
}

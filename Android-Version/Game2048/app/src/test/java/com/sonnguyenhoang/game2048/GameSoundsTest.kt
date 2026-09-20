package com.sonnguyenhoang.game2048

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The cue mixer.
 *
 * What these tests protect is promptness under load. The defect they exist
 * for was a per-cue `AudioTrack` on a per-cue thread: allocation cost turned a
 * fast run of moves into a backlog that arrived long after the moves, so the
 * player heard silence and then a pile of sounds at once. A streaming mixer
 * with a bounded voice list cannot do that — the worst it can do is drop a
 * voice.
 */
class GameSoundsTest {

    /**
     * A sink that measures what was written instead of playing it.
     *
     * `write` blocks for roughly as long as the audio it was handed, because
     * that is what a real `AudioTrack` does and it is what paces the mixer.
     * Totals are counted rather than buffers kept: an unbounded recording
     * would run the JVM out of memory long before it proved anything.
     */
    private class RecordingSink(private val failToStart: Boolean = false) : GameSounds.ToneSink {
        @Volatile var starts = 0
        @Volatile var stops = 0
        @Volatile private var frames = 0
        @Volatile private var loudFrames = 0
        @Volatile private var peak = 0
        private val firstWrite = CountDownLatch(1)

        override fun start(): Boolean {
            starts += 1
            return !failToStart
        }

        override fun write(buffer: ShortArray, frames: Int) {
            var loud = 0
            var high = 0
            for (index in 0 until frames) {
                val magnitude = kotlin.math.abs(buffer[index].toInt())
                if (magnitude > 0) loud += 1
                if (magnitude > high) high = magnitude
            }
            synchronized(this) {
                this.frames += frames
                loudFrames += loud
                if (high > peak) peak = high
            }
            firstWrite.countDown()
            Thread.sleep(frames * 1_000L / GameSounds.SAMPLE_RATE)
        }

        override fun stop() {
            stops += 1
        }

        fun awaitAudio(): Boolean = firstWrite.await(3, TimeUnit.SECONDS)
        fun peak(): Int = synchronized(this) { peak }
        fun audibleSeconds(): Double = synchronized(this) { loudFrames.toDouble() / GameSounds.SAMPLE_RATE }
    }

    private fun sounds(sink: GameSounds.ToneSink, idleReleaseMs: Long = GameSounds.IDLE_RELEASE_MS) =
        GameSounds(FakeSharedPreferences(), sink, idleReleaseMs)

    @Test
    fun `a cue reaches the device and the mixer shuts itself down afterwards`() {
        val sink = RecordingSink()
        val sounds = sounds(sink)

        sounds.move()

        assertTrue("a cue must be audible promptly, not eventually", sink.awaitAudio())
        assertTrue("and must contain signal", sink.peak() > 0)
        sounds.release()
        assertEquals(1, sink.starts)
        assertEquals(1, sink.stops)
    }

    @Test
    fun `a flood of cues is capped rather than buffered`() {
        // A player holding a key cannot make the mixer owe them sound. Two
        // hundred 50 ms cues played in turn would be ten seconds of audio;
        // the cap means at most a handful sound at once and the rest are
        // dropped, so the total is a fraction of a second.
        val sink = RecordingSink()
        val sounds = sounds(sink, idleReleaseMs = 50)
        repeat(200) { sounds.move() }

        assertTrue(sink.awaitAudio())
        Thread.sleep(400)
        sounds.release()

        assertTrue("wrote ${sink.audibleSeconds()} s of audio", sink.audibleSeconds() < 1.0)
    }

    @Test
    fun `muting silences every cue and is remembered`() {
        val preferences = FakeSharedPreferences()
        val sink = RecordingSink()
        val sounds = GameSounds(preferences, sink)

        assertTrue(sounds.isEnabled)
        assertFalse(sounds.toggle())

        sounds.move()
        sounds.merge(64)
        sounds.undo()
        sounds.newGame()
        sounds.win()
        sounds.gameOver()
        sounds.invalid()

        assertEquals("a muted cue never opens the device", 0, sink.starts)
        assertFalse(GameSounds(preferences, RecordingSink()).isEnabled)
        sounds.release()
    }

    @Test
    fun `an unavailable audio device costs the game nothing`() {
        val sink = RecordingSink(failToStart = true)
        val sounds = sounds(sink)

        sounds.move()
        sounds.gameOver()
        Thread.sleep(100)
        sounds.release()

        assertEquals(0.0, sink.audibleSeconds(), 0.0)
    }

    @Test
    fun `the mixer releases the device once the cues stop`() {
        // A puzzle game has no business holding an audio device between moves.
        val sink = RecordingSink()
        val sounds = sounds(sink, idleReleaseMs = 60)

        sounds.move()
        assertTrue(sink.awaitAudio())

        val released = (0 until 300).any {
            Thread.sleep(10)
            sink.stops > 0
        }
        assertTrue("the track must be released after the idle window", released)

        // And the next cue opens it again rather than staying silent.
        sounds.move()
        val reopened = (0 until 300).any {
            Thread.sleep(10)
            sink.starts > 1
        }
        assertTrue("a cue after the idle window must still be heard", reopened)
        sounds.release()
    }

    @Test
    fun `every cue produces audible signal`() {
        for (cue in listOf<GameSounds.(Unit) -> Unit>(
            { move() }, { merge(64) }, { undo() }, { newGame() }, { win() }, { gameOver() }, { invalid() }
        )) {
            val sink = RecordingSink()
            val sounds = sounds(sink)
            sounds.cue(Unit)
            assertTrue(sink.awaitAudio())
            // Delayed notes need a moment; the first buffer may be the lead-in.
            val audible = (0 until 200).any {
                Thread.sleep(10)
                sink.peak() > 0
            }
            sounds.release()
            assertTrue("a cue that writes only silence is a broken cue", audible)
        }
    }
}

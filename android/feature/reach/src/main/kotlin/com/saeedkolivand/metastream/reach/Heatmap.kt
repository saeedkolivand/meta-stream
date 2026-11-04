package com.saeedkolivand.metastream.reach

import java.text.DateFormatSymbols
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

/**
 * The best-time heatmap (iOS HeatmapView): weekday x hour over every recorded sample, in the device's time zone. Needs 10
 * streams; a slot seen in fewer than 2 streams doesn't count (one stream proves nothing).
 */
object Heatmap {
    const val MIN_STREAMS = 10

    enum class Metric(val title: String) { Viewers("Avg viewers"), Donations("Donations / h"), Chatters("New chatters / h") }

    /** [weekday] 0 = Monday. */
    class Cell(val weekday: Int, val hour: Int, val value: Double, val sessions: Int) {
        val enough get() = sessions >= 2
    }

    private class Bucket(var sum: Double = 0.0, var count: Int = 0, val sessions: HashSet<Long> = HashSet())

    /** Viewers: mean over samples with viewers; donations and new chatters: the sum scaled to one hour of samples. */
    fun cells(records: List<SessionRecord>, metric: Metric, tz: TimeZone = TimeZone.getDefault()): List<Cell> {
        val buckets = HashMap<Int, Bucket>()
        val cal = Calendar.getInstance(tz)
        for (r in records) {
            for (s in r.samples) {
                val v = when (metric) {
                    Metric.Viewers -> s.viewers.takeIf { it > 0 }?.toDouble()
                    Metric.Donations -> s.donations
                    Metric.Chatters -> s.newChatters.toDouble()
                } ?: continue
                cal.timeInMillis = r.start + (s.minute - 1) * 60_000L
                val key = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 * 24 + cal.get(Calendar.HOUR_OF_DAY) // Calendar: 1 = Sunday
                val b = buckets.getOrPut(key) { Bucket() }
                b.sum += v
                b.count++
                b.sessions += r.start
            }
        }
        return buckets.map { (k, b) ->
            Cell(k / 24, k % 24, if (metric == Metric.Viewers) b.sum / b.count else b.sum * 60 / b.count, b.sessions.size)
        }.sortedBy { it.weekday * 24 + it.hour }
    }

    /** "Sunday 18:00–19:00, 26 viewers on average": the strongest slot seen in at least 2 streams. */
    fun bestSlot(records: List<SessionRecord>): String? {
        if (records.size < MIN_STREAMS) return null
        val best = cells(records, Metric.Viewers).filter { it.enough }.maxByOrNull { it.value } ?: return null
        val day = DateFormatSymbols.getInstance(Locale.getDefault()).weekdays[(best.weekday + 1) % 7 + 1]
        fun h(v: Int) = "%02d:00".format(v % 24)
        return "$day ${h(best.hour)}–${h(best.hour + 1)}, ${best.value.roundToInt()} viewers on average"
    }
}

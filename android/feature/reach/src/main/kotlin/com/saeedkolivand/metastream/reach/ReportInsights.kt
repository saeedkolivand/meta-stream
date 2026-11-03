package com.saeedkolivand.metastream.reach

import kotlin.math.roundToInt

/** What the Session report derives from one record and the older ones (iOS ReportInsights). Pure: no disk, no views. */
class ReportInsights(val record: SessionRecord, history: List<SessionRecord>) {
    data class Delta(val label: String, val value: String, val percent: Int?)

    private val others = history.filter { it.start != record.start }

    /** Up to 10 sessions before this one, newest first; deltas show only with 3 or more. */
    val baseline = others.filter { it.start < record.start }.sortedByDescending { it.start }.take(10)
    val showDeltas get() = baseline.size >= 3

    /** Ranks this stream by average viewers among the month's streams; fewer than 3 is nothing to rank. */
    val verdict: String
        get() {
            val month = WrappedBuilder.monthKey(record.start)
            val peers = others.filter { WrappedBuilder.monthKey(it.start) == month }
            if (peers.size + 1 < 3) {
                return if (peers.any { it.start < record.start }) "Your second stream this month" else "Your first stream this month"
            }
            val rank = peers.count { it.avgViewers > record.avgViewers } + 1
            return if (rank == 1) "Your best stream this month" else "Your ${ordinal(rank)} best stream this month"
        }

    fun deltas(donationText: String) = listOf(
        Delta("Average viewers", "${record.avgViewers}", percent(record.avgViewers.toDouble(), baseline.map { it.avgViewers.toDouble() })),
        Delta("Chat messages", "${chat(record)}", percent(chat(record).toDouble(), baseline.map { chat(it).toDouble() })),
        Delta("Donations", donationText, percent(record.donationTotal.toDouble(), baseline.map { it.donationTotal.toDouble() }))
    )

    /** The line under the chart for each tab. */
    fun takeaway(tab: String): String {
        val s = record.samples
        return when (tab) {
            "Chat" -> s.maxByOrNull { it.chat }?.takeIf { it.chat > 0 }?.let { "Busiest minute ${clock(it)} · ${it.chat} messages" }
                ?: "No chat this stream"
            "Bitrate" -> s.map { it.kbps }.filter { it > 0 }.takeIf { it.isNotEmpty() }
                ?.let { "Average %.1f Mbps".format(java.util.Locale.US, it.average() / 1000) } ?: "No bitrate recorded"
            else -> s.maxByOrNull { it.viewers }?.takeIf { it.viewers > 0 }?.let { "Peak ${it.viewers} at ${clock(it)}" }
                ?: "No viewers counted"
        }
    }

    private fun clock(s: SessionSample) = LivePostText.hhmm(record.start + s.minute * 60_000L)

    companion object {
        fun chat(r: SessionRecord) = r.samples.sumOf { it.chat }

        fun percent(now: Double, past: List<Double>): Int? {
            val mean = past.sum() / maxOf(past.size, 1)
            return if (mean > 0) ((now - mean) / mean * 100).roundToInt() else null
        }

        fun ordinal(n: Int): String {
            val suffix = if (n % 100 in 11..13) {
                "th"
            } else {
                when (n % 10) {
                    1 -> "st"
                    2 -> "nd"
                    3 -> "rd"
                    else -> "th"
                }
            }
            return "$n$suffix"
        }
    }
}

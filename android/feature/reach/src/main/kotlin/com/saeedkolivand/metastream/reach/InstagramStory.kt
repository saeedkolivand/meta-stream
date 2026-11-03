package com.saeedkolivand.metastream.reach

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.core.content.FileProvider
import com.saeedkolivand.metastream.BuildConfig
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.overlay.ColorTheme
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.streaming.Engine
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * "Share to Instagram story" (iOS InstagramStory): a 9:16 card (a frame of the stream, LIVE, the title and the Kick link)
 * handed to Instagram's story editor with Meta's ADD_TO_STORY intent. An app can't pre-place the Link sticker, so the card
 * prints the URL and leaves the lower third empty for it. The source app ID is the Meta Wearables one (mwdat_application_id).
 * Not on-stream, so the card is drawn once on the CPU.
 */
object InstagramStory {
    enum class Template(val title: String) { Minimal("Minimal"), FullBleed("Full bleed"), Poster("Poster"), Bilingual("Bilingual FA / EN") }

    private const val ACTION = "com.instagram.share.ADD_TO_STORY"

    // Colours follow Settings > Scenes › Theme (iOS ColorTheme), shared with the scene templates.
    private val BG get() = ColorTheme.current.bg
    private val ACCENT get() = ColorTheme.current.accent
    private val ON_ACCENT get() = ColorTheme.current.onAccent
    private val TEXT get() = ColorTheme.current.text
    private val MUTED get() = ColorTheme.current.muted

    val template get() = Template.entries.firstOrNull { it.name == Prefs.string("igStoryTemplate", "") } ?: Template.Minimal

    fun available(ctx: Context) = BuildConfig.META_APP_ID.isNotEmpty() && ctx.packageManager.resolveActivity(intent(), 0) != null

    private fun intent() = Intent(ACTION).setType("image/jpeg")

    /** While live: a frame of the output (never while blur is stalled); before GO LIVE (or [test]) a "live soon" text card. */
    suspend fun share(ctx: Context, test: Boolean = false) {
        if (!available(ctx)) return
        val live = Engine.live && !test
        val frame = if (live) LivePost.frame() else null
        val slug = Prefs.string("chatChannel", "").trim().ifEmpty { Kick.user.lowercase() }
        val file = withContext(Dispatchers.Default) {
            val card = card(frame, Kick.title, if (slug.isEmpty()) "" else "kick.com/$slug", template, soon = !Engine.live)
            File(ctx.cacheDir, "share").apply { mkdirs() }.resolve("story.jpg").also { f ->
                f.outputStream().use { card.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            }
        }
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
        val edge = "#%06X".format((if (template == Template.Poster) ACCENT else BG) and 0xFFFFFF)
        ctx.grantUriPermission("com.instagram.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(
            Intent(ACTION).setDataAndType(uri, "image/jpeg").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(
                    "source_application",
                    BuildConfig.META_APP_ID
                ).putExtra("top_background_color", edge).putExtra("bottom_background_color", edge)
        )
        applog("reach", "instagram story card handed over (frame: ${frame != null})")
    }

    /** Designed at 360x640 like iOS, drawn at x3 (1080x1920, Meta's minimum is 720x1280). */
    fun card(frame: Bitmap?, title: String, link: String, t: Template, soon: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(1080, 1920, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.scale(3f, 3f)
        c.drawColor(if (t == Template.Poster) ACCENT else BG)
        val fg = if (t == Template.Poster) ON_ACCENT else TEXT
        var y = when (t) {
            Template.Poster -> 76f
            Template.FullBleed -> 72f
            else -> 84f
        }
        if (t == Template.FullBleed) {
            frame?.let { shot(c, it, RectF(0f, 0f, 360f, 640f), 0f) }
            val top = Paint().apply { color = BG }
            c.drawRect(0f, 0f, 360f, 72f + 30f + 10f + if (title.isEmpty()) 20f else 80f, top)
            c.drawRect(0f, 640f - 96f - 18f - 72f - 20f, 360f, 640f, top)
            y = pill(c, if (soon) "LIVE SOON" else "LIVE", 14f, 20f, y) + 10f
            if (title.isNotEmpty()) text(c, title, 22f, true, fg, 20f, y, 2)
            if (link.isNotEmpty()) text(c, link, 14f, false, MUTED, 20f, 640f - 96f - 18f, 1, Layout.Alignment.ALIGN_CENTER)
            return bmp
        }
        if (t == Template.Poster) {
            y = text(c, if (soon) "LIVE\nSOON" else "LIVE\nNOW", 76f, true, fg, 24f, y, 2, spacing = 0.85f) + 14f
            if (title.isNotEmpty()) y = text(c, title, 17f, true, fg, 24f, y, 3) + 14f
        } else {
            y =
                pill(
                    c,
                    if (soon) {
                        "LIVE SOON on Kick".takeIf { t == Template.Minimal } ?: "LIVE SOON"
                    } else {
                        "LIVE on Kick".takeIf {
                            t ==
                                Template.Minimal
                        }
                            ?: "LIVE"
                    },
                    15f,
                    24f,
                    y
                )
            if (t ==
                Template.Bilingual
            ) {
                text(c, if (soon) "به‌زودی لایوم" else "الان لایوم", 18f, true, fg, 24f, y - 26f, 1, Layout.Alignment.ALIGN_OPPOSITE)
            }
            y += 16f
        }
        frame?.let { y = shot(c, it, RectF(24f, y, 336f, y + 175.5f), if (t == Template.Poster) 10f else 14f) + 16f }
        if (t != Template.Poster && title.isNotEmpty()) y = text(c, title, 24f, true, fg, 24f, y, 3) + 16f
        if (t == Template.Bilingual) y = text(c, "بیاید تو لایو، لینک پایینه", 16f, false, MUTED, 24f, y, 1) + 16f
        if (link.isNotEmpty()) {
            text(
                c,
                link,
                if (t ==
                    Template.Poster
                ) {
                    14f
                } else {
                    15f
                },
                t == Template.Poster,
                if (t == Template.Poster) fg else MUTED,
                24f,
                y,
                1
            )
        }
        return bmp
    }

    /** Accent capsule with a dot and label at (x, y); returns its bottom. */
    private fun pill(c: Canvas, label: String, size: Float, x: Float, y: Float): Float {
        val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            typeface = Typeface.DEFAULT_BOLD
            color = ON_ACCENT
        }
        val w = 12f + 8f + 6f + p.measureText(label) + 12f
        val h = size * 1.2f + 12f
        c.drawRoundRect(RectF(x, y, x + w, y + h), h / 2, h / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ACCENT })
        c.drawCircle(x + 16f, y + h / 2, 4f, p)
        c.drawText(label, x + 26f, y + h / 2 - (p.ascent() + p.descent()) / 2, p)
        return y + h
    }

    /** Wrapped, ellipsised text in a 312-wide column; returns its bottom. */
    private fun text(
        c: Canvas,
        s: String,
        size: Float,
        bold: Boolean,
        color: Int,
        x: Float,
        y: Float,
        lines: Int,
        align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL,
        spacing: Float = 1f
    ): Float {
        val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            this.color = color
        }
        val width = if (x == 20f) 320 else 312
        val l = StaticLayout.Builder.obtain(s.take(300), 0, minOf(s.length, 300), p, width).setAlignment(align).setMaxLines(lines)
            .setEllipsize(TextUtils.TruncateAt.END).setLineSpacing(0f, spacing).build()
        c.save()
        c.translate(x, y)
        l.draw(c)
        c.restore()
        return y + l.height
    }

    /** The frame, centre-cropped to fill [r] with rounded corners; returns the bottom. */
    private fun shot(c: Canvas, f: Bitmap, r: RectF, radius: Float): Float {
        val k = maxOf(r.width() / f.width, r.height() / f.height)
        val sw = (r.width() / k).toInt()
        val sh = (r.height() / k).toInt()
        val src = Rect((f.width - sw) / 2, (f.height - sh) / 2, (f.width + sw) / 2, (f.height + sh) / 2)
        c.save()
        if (radius > 0) c.clipPath(android.graphics.Path().apply { addRoundRect(r, radius, radius, android.graphics.Path.Direction.CW) })
        c.drawBitmap(f, src, r, Paint(Paint.FILTER_BITMAP_FLAG))
        c.restore()
        return r.bottom
    }
}

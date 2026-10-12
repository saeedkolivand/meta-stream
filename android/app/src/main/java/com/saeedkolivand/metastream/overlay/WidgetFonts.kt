package com.saeedkolivand.metastream.overlay

import android.content.Context
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.FontFamily
import android.graphics.fonts.FontStyle
import com.saeedkolivand.metastream.R

private val WEIGHTS = listOf(400, 600, 700)

/**
 * Fonts for everything drawn on the stream. The default face keeps Latin in the system sans and lets Persian/Arabic
 * fall through to Vazirmatn, so a mixed "gg خیلی خوب" line renders right with no per-run work.
 */
object WidgetFonts {
    private val full = HashMap<Int, Typeface>()
    private val mixed = HashMap<Int, Typeface>()

    val faces: List<Pair<String, String>> = listOf("" to "System", "Vazirmatn" to "Vazirmatn")

    /** Loads the bundled files once; before that (unit tests) [typeface] returns plain system sans. */
    fun init(ctx: Context) {
        if (full.isNotEmpty()) return
        val res = ctx.resources
        val whole = listOf(R.font.vazirmatn_regular, R.font.vazirmatn_semibold, R.font.vazirmatn_bold)
        val noLatin = listOf(R.font.vazirmatn_nl_regular, R.font.vazirmatn_nl_semibold, R.font.vazirmatn_nl_bold)
        WEIGHTS.forEachIndexed { i, w ->
            runCatching {
                full[w] = res.getFont(whole[i])
                // The NL files carry no Latin, so Latin resolves to the system fallback (Roboto) at the same weight.
                val family = FontFamily.Builder(Font.Builder(res, noLatin[i]).build()).build()
                mixed[w] = Typeface.CustomFallbackBuilder(family)
                    .setSystemFallback("sans-serif")
                    .setStyle(FontStyle(w, FontStyle.FONT_SLANT_UPRIGHT))
                    .build()
            }
        }
    }

    /** [weight] snaps to 400/600/700; an unknown [face] is the system one. */
    fun typeface(face: String, weight: Int): Typeface {
        val w = WEIGHTS.lastOrNull { weight >= it } ?: 400
        val map = if (face == "Vazirmatn") full else mixed
        return map[w] ?: Typeface.create(Typeface.DEFAULT, w, false)
    }

    /** True when the first strong character is Hebrew/Arabic-script (U+0590..U+08FF, U+FB1D..U+FEFC). */
    fun isRtl(text: String): Boolean {
        for (c in text) {
            if (c.code in 0x0590..0x08FF || c.code in 0xFB1D..0xFEFC) return true
            if (Character.isLetter(c)) return false
        }
        return false
    }
}

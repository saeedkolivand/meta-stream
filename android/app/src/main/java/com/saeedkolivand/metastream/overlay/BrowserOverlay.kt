package com.saeedkolivand.metastream.overlay

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import com.pedro.encoder.input.gl.render.filters.`object`.ViewSurfaceFilterRender
import org.json.JSONObject

// OBS's default browser source css: transparent page, no scrollbars.
private const val DEFAULT_CSS = "body { background-color: rgba(0, 0, 0, 0); margin: 0px auto; overflow: hidden; }"

private fun httpOnly(url: String) = url.startsWith("http://") || url.startsWith("https://")

/**
 * All browser sources of a scene in one output-sized view, drawn by a single ViewSurfaceFilterRender.
 * Each WebView keeps its OBS pixel size (so the page lays out like in OBS) and is scaled/moved into place with view transforms.
 * Locked down: http(s) pages only, no file access, no JavaScript bridges; URLs are never logged.
 */
internal class BrowserOverlay(private val ctx: Context, outW: Int, outH: Int) {
    private val root = FrameLayout(ctx).also { it.layoutParams = FrameLayout.LayoutParams(outW, outH) }
    private val views = mutableListOf<WebView>()

    val isEmpty get() = views.isEmpty()

    @SuppressLint("SetJavaScriptEnabled")
    fun add(l: Layer, fit: Fit) {
        val url = l.data["url"].orEmpty()
        if (!httpOnly(url)) return
        val w = l.data["width"]?.toIntOrNull() ?: 800
        val h = l.data["height"]?.toIntOrNull() ?: 600
        val box = fit.apply(place(l, w.toFloat(), h.toFloat()))
        val css = JSONObject.quote(l.data["css"].orEmpty().ifBlank { DEFAULT_CSS })
        val v = WebView(ctx)
        v.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = false
            allowContentAccess = false
            @Suppress("DEPRECATION")
            allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            allowUniversalAccessFromFileURLs = false
        }
        v.setBackgroundColor(Color.TRANSPARENT)
        v.setInitialScale(100) // 1 CSS px = 1 device px, so a 1920 wide page lays out 1920 wide
        v.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = !httpOnly(request.url.toString())

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                if (httpOnly(request.url.toString())) null else WebResourceResponse("text/plain", "utf-8", null)

            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript(
                    "(function(){var s=document.createElement('style');s.textContent=$css;document.head.appendChild(s)})()",
                    null
                )
            }
        }
        v.layoutParams = FrameLayout.LayoutParams(w, h)
        v.pivotX = w / 2f
        v.pivotY = h / 2f
        v.scaleX = box.w / w
        v.scaleY = box.h / h
        v.translationX = box.x + box.w / 2 - w / 2f
        v.translationY = box.y + box.h / 2 - h / 2f
        v.rotation = l.rotation
        root.addView(v)
        views += v
        v.loadUrl(url)
    }

    fun filter() = ViewSurfaceFilterRender().also { it.setView(root) }

    fun destroy() {
        root.removeAllViews()
        views.forEach {
            it.stopLoading()
            it.destroy()
        }
        views.clear()
    }
}

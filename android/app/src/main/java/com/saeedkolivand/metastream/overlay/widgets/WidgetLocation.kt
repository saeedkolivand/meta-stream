package com.saeedkolivand.metastream.overlay

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import androidx.core.content.ContextCompat
import java.util.Locale

private const val GEOCODE_MS = 60_000L
private const val GEOCODE_METERS = 500f
private val IMPERIAL = setOf("US", "LR", "MM")

/**
 * Speed and city for the {speed}/{city} text tokens. Updates run only while a live text widget uses them (retain/release),
 * so a scene without those tokens never touches the GPS. Permission is requested by the UI, never here; until it is
 * granted the tokens read "--", and updates start on the first read after the grant.
 */
internal object WidgetLocation {
    private var users = 0
    private var started = false
    private var mps: Float? = null
    private var city = ""
    private var geocodedAt = 0L
    private var geocodedLoc: Location? = null
    private var geocoding = false
    private val listener = LocationListener { handle(it) }

    val speedText: String
        get() {
            ensureStarted()
            val v = mps ?: return "--"
            val imperial = Locale.getDefault().country in IMPERIAL
            val n = (v * if (imperial) 2.23694f else 3.6f).toInt()
            return "$n ${if (imperial) "mph" else "km/h"}"
        }

    val cityText: String
        get() {
            ensureStarted()
            return city.ifEmpty { "--" }
        }

    fun retain() {
        users++
        ensureStarted()
    }

    fun release() {
        users = (users - 1).coerceAtLeast(0)
        if (users == 0 && started) {
            appContext.getSystemService(LocationManager::class.java).removeUpdates(listener)
            started = false
        }
    }

    private fun granted() = listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        .any { ContextCompat.checkSelfPermission(appContext, it) == PackageManager.PERMISSION_GRANTED }

    @SuppressLint("MissingPermission") // granted() checks it; runCatching absorbs a revoke-mid-call SecurityException
    private fun ensureStarted() {
        if (users == 0 || started || !granted()) return
        val lm = appContext.getSystemService(LocationManager::class.java)
        // Fused when the device has it (cheaper, indoor-capable), else raw GPS, else network.
        val provider = listOf(LocationManager.FUSED_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .firstOrNull { it in lm.allProviders && lm.isProviderEnabled(it) } ?: return
        runCatching { lm.requestLocationUpdates(provider, 1000L, 10f, listener, Looper.getMainLooper()) }
            .onSuccess { started = true }
    }

    private fun handle(loc: Location) {
        mps = if (loc.hasSpeed()) loc.speed.coerceAtLeast(0f) else 0f
        val now = System.currentTimeMillis()
        // At most one reverse geocode per 60 s and 500 m: the geocoder is rate limited and a city rarely changes.
        val prev = geocodedLoc
        if (geocoding || (prev != null && (now - geocodedAt < GEOCODE_MS || loc.distanceTo(prev) < GEOCODE_METERS))) return
        if (!Geocoder.isPresent()) return
        geocoding = true
        geocodedAt = now
        geocodedLoc = loc
        Geocoder(appContext, Locale.getDefault()).getFromLocation(
            loc.latitude,
            loc.longitude,
            1,
            object : Geocoder.GeocodeListener {
                override fun onGeocode(addresses: MutableList<Address>) {
                    addresses.firstOrNull()?.locality?.let { city = it }
                    geocoding = false
                }

                override fun onError(errorMessage: String?) {
                    geocoding = false
                }
            }
        )
    }
}

package com.saeedkolivand.metastream.core

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/** The one SharedPreferences file. */
object Prefs {
    private lateinit var sp: SharedPreferences

    fun init(context: Context) {
        sp = context.getSharedPreferences("ingest", Context.MODE_PRIVATE)
    }

    fun string(key: String, default: String = ""): String = sp.getString(key, default) ?: default

    fun bool(key: String, default: Boolean = false): Boolean = sp.getBoolean(key, default)

    fun int(key: String, default: Int): Int = sp.getInt(key, default)

    fun put(key: String, value: String) = sp.edit { putString(key, value) }

    fun put(key: String, value: Boolean) = sp.edit { putBoolean(key, value) }

    fun put(key: String, value: Int) = sp.edit { putInt(key, value) }
}

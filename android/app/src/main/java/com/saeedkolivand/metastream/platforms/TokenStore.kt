package com.saeedkolivand.metastream.platforms

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.edit
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.redactFromLogs
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * OAuth tokens, AES-256-GCM encrypted with a non-exportable Android Keystore key (androidx security-crypto is deprecated).
 * The prefs file only ever holds `base64(iv + ciphertext)`; every token read is also registered for log redaction.
 */
internal object TokenStore {
    private const val ALIAS = "metastream.tokens"
    private lateinit var sp: SharedPreferences

    fun init(context: Context) {
        sp = context.getSharedPreferences("tokens", Context.MODE_PRIVATE)
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(spec) }.generateKey()
    }

    fun has(name: String) = sp.contains(name)

    fun get(name: String): String? {
        val blob = sp.getString(name, null) ?: return null
        return try {
            val raw = Base64.decode(blob, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, IV_BYTES))
            }
            String(cipher.doFinal(raw, IV_BYTES, raw.size - IV_BYTES)).also(::redactFromLogs)
        } catch (e: java.security.GeneralSecurityException) {
            // Key lost (e.g. device re-secured): treat as signed out rather than crash.
            applog("auth", "token $name unreadable: ${e.javaClass.simpleName}")
            null
        }
    }

    fun set(name: String, value: String) {
        redactFromLogs(value)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) } // fresh random IV per write
        val blob = cipher.iv + cipher.doFinal(value.toByteArray())
        sp.edit { putString(name, Base64.encodeToString(blob, Base64.NO_WRAP)) }
    }

    /** Drops `<prefix>Access`, `Refresh` and `Scopes`. */
    fun forget(prefix: String) = sp.edit { listOf("Access", "Refresh", "Scopes").forEach { remove(prefix + it) } }

    private const val IV_BYTES = 12
}

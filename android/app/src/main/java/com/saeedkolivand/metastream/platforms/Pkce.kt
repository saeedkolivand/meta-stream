package com.saeedkolivand.metastream.platforms

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** PKCE (RFC 7636) helpers; also the source of OAuth `state` values. */
internal object Pkce {
    private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    private val rng = SecureRandom()

    /** [n] random unreserved characters (a valid code_verifier for 43..128, or a state). */
    fun random(n: Int) = String(CharArray(n) { UNRESERVED[rng.nextInt(UNRESERVED.length)] })

    /** code_challenge for method S256: base64url(sha256(verifier)) without padding. */
    fun s256(verifier: String): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))
}

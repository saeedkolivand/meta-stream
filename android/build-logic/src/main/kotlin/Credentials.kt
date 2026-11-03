import java.util.Properties
import org.gradle.api.Project

/** A value from the root local.properties (dev builds); empty when missing. */
fun Project.localProperty(name: String): String {
    val file = rootDir.resolve("local.properties")
    if (!file.exists()) return ""
    return Properties().apply { file.inputStream().use { load(it) } }.getProperty(name, "").trim()
}

/** OAuth/app credentials: CI env vars win, local.properties for dev builds; empty means the app shows "no client ID". */
fun Project.credential(name: String): String =
    (System.getenv(name)?.takeIf { it.isNotBlank() } ?: localProperty(name)).trim().replace("\"", "")

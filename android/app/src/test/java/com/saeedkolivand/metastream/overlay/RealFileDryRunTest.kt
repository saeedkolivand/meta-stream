package com.saeedkolivand.metastream.overlay

import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Manual: set OBS_DRYRUN=<path to a scene collection>. Prints scene names, layer types and counts only, never URLs. */
class RealFileDryRunTest {
    @Test fun dryRun() {
        val path = System.getenv("OBS_DRYRUN")
        assumeTrue(path != null)
        val pack = parseObs(File(path!!).readText())
        println("DRYRUN scenes=${pack.scenes.size} files=${pack.files().size} skipped=${pack.skipped}")
        for (s in pack.scenes) {
            val counts = s.layers.groupingBy { it.type }.eachCount()
            println("DRYRUN scene '${s.name}' layers=${s.layers.size} visible=${s.layers.count { it.visible }} $counts")
        }
    }
}

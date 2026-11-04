package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.overlay.widgets.goal.GoalMotion
import com.saeedkolivand.metastream.overlay.widgets.goal.goalPct
import org.junit.Assert.assertEquals
import org.junit.Test

class GoalMotionTest {
    @Test
    fun windowsAndKeyframes() {
        assertEquals(0.5f, GoalMotion.seg(0.5f, 0f, 1f), 0f)
        assertEquals(1f, GoalMotion.move(0.75f), 0f)
        assertEquals(0f, GoalMotion.lp(0f, 44f, 52f), 0f) // the reaction starts at 40 % of the board loop
        assertEquals(1f, GoalMotion.lp(1f, 44f, 52f), 0f)
        // The hairline tip: 1 -> 1.8 at loop 48 % (t = 8/35) -> back to 1 by the settled frame.
        assertEquals(1.8f, GoalMotion.kf(8f / 35, 40f to 1f, 48f to 1.8f, 66f to 1f), 0.001f)
        assertEquals(1f, GoalMotion.kf(1f, 40f to 1f, 48f to 1.8f, 66f to 1f), 0f)
        assertEquals(0f, GoalMotion.kf(1f, 50f to 0f, 52f to 1f, 72f to 0f, delay = 2.64f), 0f)
        assertEquals("100%", goalPct(1.4f))
    }
}

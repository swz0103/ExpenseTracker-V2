package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateFeedTest {
    @Test
    fun readsTheBuildOfUpdateJson() {
        assertEquals(412, UpdateFeed.build("""{"build":412,"version":"0.9.1","sha256":"x","size":1}"""))
        assertNull(UpdateFeed.build("<html>not found</html>"))
        assertNull(UpdateFeed.build("""{"version":"0.9.1"}"""))
    }

    @Test
    fun saysANewerBuildOnce() {
        assertTrue(UpdateFeed.worthSaying(current = 400, newest = 412, said = 0))
        assertFalse(UpdateFeed.worthSaying(current = 400, newest = 412, said = 412))
        assertTrue(UpdateFeed.worthSaying(current = 400, newest = 413, said = 412))
        assertFalse(UpdateFeed.worthSaying(current = 412, newest = 412, said = 0))
    }
}

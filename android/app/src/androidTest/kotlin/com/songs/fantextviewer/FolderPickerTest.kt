package com.songs.fantextviewer

import android.content.Context
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import java.io.File
import java.util.regex.Pattern
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FolderPickerTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = instrumentation.targetContext

    @Before
    fun prepareFolderAndLaunchApp() {
        device.executeShellCommand(
            "appops set --uid ${context.packageName} MANAGE_EXTERNAL_STORAGE allow",
        )
        val folder = File("/storage/emulated/0/Download/FanTextViewerSmoke")
        assertTrue("Could not create $folder", folder.mkdirs() || folder.isDirectory)
        writePattern(
            File(folder, "cp949-5mb.txt"),
            5 * 1024 * 1024,
            byteArrayOf(0xb0.toByte(), 0xa1.toByte(), '\n'.code.toByte()),
        )
        writePattern(
            File(folder, "utf8-20mb.txt"),
            20 * 1024 * 1024,
            "UTF-8 large Android fixture\n".toByteArray(),
        )
        device.executeShellCommand(
            "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE " +
                "-d file:///sdcard/Download/FanTextViewerSmoke/cp949-5mb.txt",
        )
        device.executeShellCommand(
            "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE " +
                "-d file:///sdcard/Download/FanTextViewerSmoke/utf8-20mb.txt",
        )
        context.startActivity(
            checkNotNull(context.packageManager.getLaunchIntentForPackage(context.packageName))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
        )
    }

    private fun writePattern(file: File, size: Int, pattern: ByteArray) {
        val buffer = ByteArray(60 * 1024) { pattern[it % pattern.size] }
        file.outputStream().buffered().use { output ->
            var remaining = size
            while (remaining > 0) {
                val count = minOf(remaining, buffer.size)
                output.write(buffer, 0, count)
                remaining -= count
            }
        }
        assertTrue("Expected $size bytes at $file", file.length() == size.toLong())
    }

    @Test
    fun selectedFolderOpensRealLargeFilesWithinMemoryLimit() {
        find(By.desc("파일 탐색")).click()
        find(By.desc("폴더 선택")).click()

        var folder =
            device.wait(
                Until.findObject(documentItem(Pattern.compile("FanTextViewerSmoke"))),
                3_000,
            )
        if (folder == null) {
            var downloads =
                device.wait(
                    Until.findObject(
                        documentItem(Pattern.compile("(?i)downloads?")),
                    ),
                    3_000,
                )
            if (downloads == null) {
                device.findObject(By.descContains("Show roots"))?.click()
                downloads = find(documentItem(Pattern.compile("(?i)downloads?")))
            }
            downloads.click()
            folder = find(documentItem(Pattern.compile("FanTextViewerSmoke")))
        }
        folder.click()
        val useFolder =
            find(By.text(Pattern.compile("(?i)use this folder")).enabled(true))
        useFolder.click()
        device.wait(
            Until.findObject(By.text(Pattern.compile("(?i)allow"))),
            2_000,
        )?.click()

        openAndWait("cp949-5mb.txt")
        assertProcessPssBelow(512 * 1024)

        device.pressBack()
        find(By.desc("폴더 선택"), 20_000)
        openAndWait("utf8-20mb.txt")
        assertProcessPssBelow(512 * 1024)
    }

    private fun openAndWait(fileName: String) {
        find(By.descContains(fileName), 20_000).click()
        find(By.desc("북마크 추가"), 60_000)
    }

    private fun assertProcessPssBelow(maximumKb: Int) {
        val dump = device.executeShellCommand("dumpsys meminfo ${context.packageName}")
        val totalPss =
            Regex("""TOTAL PSS:\s+(\d+)""").find(dump)?.groupValues?.get(1)?.toInt()
                ?: Regex("""(?m)^\s*TOTAL\s+(\d+)""")
                    .find(dump)
                    ?.groupValues
                    ?.get(1)
                    ?.toInt()
        assertTrue("Could not read TOTAL PSS:\n$dump", totalPss != null)
        assertTrue(
            "Process PSS ${totalPss}KB exceeded ${maximumKb}KB",
            totalPss!! < maximumKb,
        )
    }

    private fun documentItem(title: Pattern) =
        By.res("com.google.android.documentsui", "item_root")
            .hasDescendant(By.text(title))

    private fun find(selector: androidx.test.uiautomator.BySelector, timeout: Long = 15_000): UiObject2 =
        checkNotNull(device.wait(Until.findObject(selector), timeout)) {
            "UI object not found: $selector"
        }
}

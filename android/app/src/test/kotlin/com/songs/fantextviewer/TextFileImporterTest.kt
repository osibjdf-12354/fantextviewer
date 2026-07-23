package com.songs.fantextviewer

import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextFileImporterTest {
    @Test
    fun `copies a stream to a stable sanitized destination`() {
        val root = Files.createTempDirectory("fantextviewer-import").toFile()
        try {
            val importer = TextFileImporter(maxBytes = 64)

            val target =
                importer.copy(
                    input = ByteArrayInputStream("first".toByteArray()),
                    destinationRoot = root,
                    stableId = "same-uri",
                    displayName = "../novel?.txt",
                )

            assertEquals(File(root, "same-uri/novel_.txt"), target)
            assertArrayEquals("first".toByteArray(), target.readBytes())
            assertFalse(target.parentFile?.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `same source replaces its stable copy`() {
        val root = Files.createTempDirectory("fantextviewer-reimport").toFile()
        try {
            val importer = TextFileImporter(maxBytes = 64)
            val first =
                importer.copy(
                    ByteArrayInputStream("first".toByteArray()),
                    root,
                    "same-uri",
                    "novel.txt",
                )
            val second =
                importer.copy(
                    ByteArrayInputStream("second".toByteArray()),
                    root,
                    "same-uri",
                    "renamed-by-provider.txt",
                )

            assertEquals(first, second)
            assertArrayEquals("second".toByteArray(), second.readBytes())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `oversized import preserves the previous stable copy`() {
        val root = Files.createTempDirectory("fantextviewer-limit").toFile()
        try {
            val importer = TextFileImporter(maxBytes = 5)
            val target =
                importer.copy(
                    ByteArrayInputStream("first".toByteArray()),
                    root,
                    "same-uri",
                    "novel.txt",
                )

            val error =
                runCatching {
                    importer.copy(
                        ByteArrayInputStream("too-long".toByteArray()),
                        root,
                        "same-uri",
                        "novel.txt",
                    )
                }.exceptionOrNull()

            assertTrue(error is TextFileTooLargeException)
            assertArrayEquals("first".toByteArray(), target.readBytes())
            assertFalse(target.parentFile?.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
        } finally {
            root.deleteRecursively()
        }
    }
}

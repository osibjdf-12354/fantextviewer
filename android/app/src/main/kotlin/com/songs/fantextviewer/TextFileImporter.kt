package com.songs.fantextviewer

import java.io.File
import java.io.IOException
import java.io.InputStream

class TextFileTooLargeException(
    val maximumBytes: Long,
) : IOException("Text file exceeds the $maximumBytes byte import limit")

class TextFileImporter(
    private val maxBytes: Long,
) {
    fun copy(
        input: InputStream,
        destinationRoot: File,
        stableId: String,
        displayName: String,
    ): File {
        val directory = File(destinationRoot, sanitizeStableId(stableId))
        check(directory.mkdirs() || directory.isDirectory) {
            "Could not create the imported text directory"
        }
        val existing =
            directory
                .listFiles()
                .orEmpty()
                .filter {
                    it.isFile &&
                        !it.name.endsWith(".tmp") &&
                        !it.name.endsWith(".bak")
                }.maxWithOrNull(compareBy<File>({ it.lastModified() }, { it.name }))
        val target = existing ?: File(directory, sanitizeDisplayName(displayName))
        val temporary = File.createTempFile(".${target.name}.", ".tmp", directory)
        try {
            input.use { source ->
                temporary.outputStream().buffered().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > maxBytes) {
                            throw TextFileTooLargeException(maxBytes)
                        }
                        output.write(buffer, 0, count)
                    }
                    output.flush()
                }
            }
            replace(temporary, target)
            return target
        } finally {
            temporary.delete()
        }
    }

    private fun replace(
        temporary: File,
        target: File,
    ) {
        if (temporary.renameTo(target)) return
        if (!target.exists()) {
            throw IOException("Could not install imported text file")
        }
        val backup = File.createTempFile(".${target.name}.", ".bak", target.parentFile)
        backup.delete()
        if (!target.renameTo(backup)) {
            throw IOException("Could not preserve previous imported text file")
        }
        if (temporary.renameTo(target)) {
            backup.delete()
            return
        }
        backup.renameTo(target)
        throw IOException("Could not replace imported text file")
    }

    private fun sanitizeStableId(value: String): String {
        val sanitized = value.replace(Regex("""[^\p{L}\p{N}._-]"""), "_")
        return if (sanitized.isBlank() || sanitized == "." || sanitized == "..") {
            "imported"
        } else {
            sanitized
        }
    }

    private fun sanitizeDisplayName(value: String): String {
        val leaf = value.substringAfterLast('/').substringAfterLast('\\')
        val sanitized =
            leaf
                .replace(Regex("""[^\p{L}\p{N}._ -]"""), "_")
                .trim()
        return if (sanitized.isBlank() || sanitized == "." || sanitized == "..") {
            "imported.txt"
        } else {
            sanitized
        }
    }
}

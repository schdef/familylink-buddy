package com.familylink.buddy.child

import com.familylink.buddy.child.data.PackageInstallerHelper
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile

class PackageInstallerLogicTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun testIsApkValidWithNullOrNonExistentFile() {
        assertFalse(PackageInstallerHelper.isApkValid(null))
        assertFalse(PackageInstallerHelper.isApkValid(File("non_existent_path.apk")))
    }

    @Test
    fun testIsApkValidWithEmptyOrSmallFile() {
        val emptyFile = tempFolder.newFile("empty.apk")
        assertFalse(PackageInstallerHelper.isApkValid(emptyFile))

        // 500 KB file (still too small for valid release apk)
        val smallFile = tempFolder.newFile("small.apk")
        val rafSmall = RandomAccessFile(smallFile, "rw")
        rafSmall.setLength(500 * 1024)
        rafSmall.close()
        assertFalse(PackageInstallerHelper.isApkValid(smallFile))
    }

    @Test
    fun testIsApkValidWithPlausibleSize() {
        // File > 1MB (e.g. 2MB)
        val validFile = tempFolder.newFile("release.apk")
        val rafValid = RandomAccessFile(validFile, "rw")
        rafValid.setLength(2 * 1024 * 1024)
        rafValid.close()
        assertTrue(PackageInstallerHelper.isApkValid(validFile))
    }
}

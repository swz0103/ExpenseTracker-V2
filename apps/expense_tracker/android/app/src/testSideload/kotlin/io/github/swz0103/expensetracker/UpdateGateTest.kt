package io.github.swz0103.expensetracker

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * The checks before a downloaded APK is handed to Android's installer.
 * The platform is a fake [ApkInspector]; the file is a real temp file
 * whose content is "abc" (3 bytes), whose SHA-256 is known from sha256sum.
 */
class UpdateGateTest {
    private val abcSha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private val installed = PackageFacts("io.github.swz0103.expensetracker", 100, setOf("aa", "bb"))
    private lateinit var apk: File

    @Before
    fun makeFile() {
        apk = File.createTempFile("update", ".apk")
        apk.writeText("abc")
    }

    @After
    fun removeFile() {
        apk.delete()
    }

    private fun gate(found: PackageFacts?, maxBytes: Long = 1000) =
        UpdateGate(installed, { found }, maxBytes)

    private fun newer(
        name: String = installed.packageName,
        code: Long = 101,
        signers: Set<String> = installed.signers,
    ) = PackageFacts(name, code, signers)

    @Test
    fun aNewerVersionOfThisAppSignedTheSameIsAllowed() {
        assertEquals(UpdateVerdict.OK, gate(newer()).check(apk, abcSha))
    }

    @Test
    fun theHashIsReadAsUpperCaseToo() {
        assertEquals(UpdateVerdict.OK, gate(newer()).check(apk, abcSha.uppercase()))
    }

    @Test
    fun aFileOverTheLimitIsRefusedBeforeItIsRead() {
        // 3 bytes against a limit of 2; the inspector must not even be asked.
        val gate = UpdateGate(installed, { error("must not be read") }, 2)
        assertEquals(UpdateVerdict.TOO_LARGE, gate.check(apk, abcSha))
    }

    @Test
    fun aFileExactlyAtTheLimitIsAllowed() {
        assertEquals(UpdateVerdict.OK, gate(newer(), maxBytes = 3).check(apk, abcSha))
    }

    @Test
    fun aDifferentHashIsDamaged() {
        assertEquals(UpdateVerdict.DAMAGED, gate(newer()).check(apk, "0".repeat(64)))
    }

    @Test
    fun aMissingFileIsDamaged() {
        val gone = File(apk.path + ".gone")
        assertEquals(UpdateVerdict.DAMAGED, gate(newer()).check(gone, abcSha))
    }

    @Test
    fun anApkAndroidCannotReadIsUnreadable() {
        assertEquals(UpdateVerdict.UNREADABLE, gate(null).check(apk, abcSha))
    }

    @Test
    fun anotherPackageIsRefused() {
        assertEquals(
            UpdateVerdict.WRONG_PACKAGE,
            gate(newer(name = "com.example.other")).check(apk, abcSha),
        )
    }

    @Test
    fun theSameVersionCodeIsNotNewer() {
        assertEquals(UpdateVerdict.NOT_NEWER, gate(newer(code = 100)).check(apk, abcSha))
    }

    @Test
    fun anOlderVersionCodeIsNotNewer() {
        assertEquals(UpdateVerdict.NOT_NEWER, gate(newer(code = 99)).check(apk, abcSha))
    }

    @Test
    fun aVersionCodeAboveTheIntRangeStillCounts() {
        // Version codes are longs from API 28: 2^31 = 2147483648 is above 100.
        assertEquals(UpdateVerdict.OK, gate(newer(code = 2147483648L)).check(apk, abcSha))
    }

    @Test
    fun anotherSigningKeyIsRefused() {
        assertEquals(
            UpdateVerdict.WRONG_SIGNER,
            gate(newer(signers = setOf("cc"))).check(apk, abcSha),
        )
    }

    @Test
    fun aSubsetOrSupersetOfSignersIsRefused() {
        assertEquals(UpdateVerdict.WRONG_SIGNER, gate(newer(signers = setOf("aa"))).check(apk, abcSha))
        assertEquals(
            UpdateVerdict.WRONG_SIGNER,
            gate(newer(signers = setOf("aa", "bb", "cc"))).check(apk, abcSha),
        )
    }

    @Test
    fun anApkWithoutSignersIsRefused() {
        assertEquals(UpdateVerdict.WRONG_SIGNER, gate(newer(signers = emptySet())).check(apk, abcSha))
    }

    @Test
    fun theHashIsCheckedBeforeTheApkIsRead() {
        // A damaged file never reaches the platform's parser.
        val gate = UpdateGate(installed, { error("must not be read") }, 1000)
        assertEquals(UpdateVerdict.DAMAGED, gate.check(apk, "0".repeat(64)))
    }

    @Test
    fun aCertificateDigestIsSha256InHex() {
        // sha256("abc"), as in sha256sum.
        assertEquals(abcSha, UpdateGate.digestOf("abc".toByteArray()))
        assertFalse(UpdateGate.digestOf(ByteArray(0)).isEmpty())
    }
}

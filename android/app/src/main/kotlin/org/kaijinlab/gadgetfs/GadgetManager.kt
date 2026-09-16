package org.kaijinlab.gadgetfs

import android.content.Context
import android.util.Log
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.util.ArrayList
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.min

class GadgetManager(
    private val context: Context,
    private val log: LogBus,
) {
    private val main = Handler(Looper.getMainLooper())
    private val root = RootShell(log)
    private val prefs = Prefs(context)
    private val udcNameRegex = Regex("^[A-Za-z0-9._-]+$")

    // Persistent writer FD semantics (RootShell uses FD 3/4 internally)
    private val HID_KBD_FD = 3
    private val HID_MOUSE_FD = 4

    @Volatile private var inMemoryKbdDev: String? = null
    @Volatile private var inMemoryMouseDev: String? = null

    @Volatile private var lastLoggedButtons: Int = -1
    @Volatile private var lastMouseMoveLogTime: Long = 0L
    @Volatile private var lastWriterAttemptMs: Long = 0L

    /**
     * Keyboard timing: we must hold a key "down" long enough that the host polling interval
     * will actually observe it. This is why we do down -> usleep -> up.
     */
    private val keyDownHoldUs: Int = 9000
    private val interKeyDelayUs: Int = 1500

    /**
     * Avoid building extremely large scripts. We chunk text typing into batches.
     * With a persistent su session, you can safely raise this somewhat, but keep it bounded.
     */
    private val maxTypedCharsPerBatch: Int = 60

    data class Status(
        val rootAvailable: Boolean,
        val supportAvailable: Boolean,
        val udcList: List<String>,
        val state: String,
        val activeProfileId: String?,
        val message: String?,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "rootAvailable" to rootAvailable,
            "supportAvailable" to supportAvailable,
            "udcList" to udcList,
            "state" to state,
            "activeProfileId" to activeProfileId,
            "message" to message,
        )
    }

    private val statusRef = AtomicReference(
        Status(
            rootAvailable = false,
            supportAvailable = false,
            udcList = emptyList(),
            state = "IDLE",
            activeProfileId = null,
            message = null,
        )
    )
    private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)

    init {
        refreshAndEmitStatus(restoreFromPrefs = true)
    }

    fun attachStatusSink(sink: EventChannel.EventSink) {
        sinkRef.set(sink)
        val snap = statusRef.get().toMap()
        main.post {
            try {
                sink.success(snap)
            } catch (_: Throwable) {
            }
        }
    }

    fun detachStatusSink() {
        sinkRef.set(null)
    }

    fun getStatusSnapshot(): Status {
        return refreshAndEmitStatus(restoreFromPrefs = true)
    }

    fun refreshAndEmitStatus(restoreFromPrefs: Boolean = true): Status {
        val current = statusRef.get()
        val rootOk = checkRoot()
        val configfsOk = rootOk && ensureConfigfsAvailable()
        val udcs = if (rootOk) listUdcs() else emptyList()
        val supportOk = rootOk && configfsOk && udcs.isNotEmpty()

        var state = current.state
        var activeId = current.activeProfileId
        var msg = current.message

        if (rootOk) {
            if (state == "ACTIVE") {
                val activeDir = prefs.activeGadgetDir
                val stillActive = !activeDir.isNullOrBlank() && isGadgetDirBound(activeDir)
                if (!stillActive) {
                    if (!discoverAndRecoverActiveGadget()) {
                        state = "IDLE"
                        activeId = prefs.activeProfileId
                        msg = null
                        closeHidWritersBestEffort()
                        stopForeground()
                        log.log("gadget", "Gadget was unbound externally; state reset to IDLE")
                    } else {
                        activeId = prefs.activeProfileId
                    }
                } else {
                    val kbd = inMemoryKbdDev ?: prefs.activeKeyboardDev
                    val mouse = inMemoryMouseDev ?: prefs.activeMouseDev
                    if ((kbd != null && !root.isKeyboardWriterReady()) || (mouse != null && !root.isMouseWriterReady())) {
                        openHidWritersBestEffort(kbd, mouse)
                    }
                }
            } else {
                if (restoreFromPrefs) {
                    if (discoverAndRecoverActiveGadget()) {
                        state = "ACTIVE"
                        activeId = prefs.activeProfileId
                        msg = null
                    } else {
                        if (state != "ACTIVATING") {
                            state = "IDLE"
                            activeId = prefs.activeProfileId
                        }
                    }
                }
            }
        } else {
            if (state == "ACTIVE") {
                state = "IDLE"
                activeId = null
            }
        }

        val next = Status(
            rootAvailable = rootOk,
            supportAvailable = supportOk,
            udcList = udcs,
            state = state,
            activeProfileId = activeId,
            message = msg,
        )
        statusRef.set(next)
        emit(next)
        return next
    }

    fun checkRoot(): Boolean = root.hasRoot()

    fun checkSupport(): Boolean {
        if (!checkRoot()) return false
        if (!ensureConfigfsAvailable()) return false
        return listUdcs().isNotEmpty()
    }

    fun listUdcs(): List<String> {
        val r = root.exec("ls -1 /sys/class/udc 2>/dev/null || true")
        val items = r.stdout
            .lineSequence()
            .map { it.trim().trim('\r') }
            .filter { it.isNotBlank() }
            .filter { udcNameRegex.matches(it) }
            .toList()
        if (items.isNotEmpty()) return items

        val p = root.exec("getprop sys.usb.controller 2>/dev/null || true")
        val lines = p.stdout
            .lineSequence()
            .map { it.trim().trim('\r') }
            .filter { it.isNotBlank() }
            .toList()

        val direct = lines.firstOrNull { udcNameRegex.matches(it) }
        if (!direct.isNullOrBlank()) return listOf(direct)

        val dumpLine = lines.firstOrNull { it.startsWith("[sys.usb.controller]") }
        if (!dumpLine.isNullOrBlank()) {
            val m = Regex("\\[sys\\.usb\\.controller\\]: \\[(.*)]").find(dumpLine)
            val v = m?.groupValues?.getOrNull(1)?.trim()
            if (!v.isNullOrBlank() && udcNameRegex.matches(v)) return listOf(v)
        }
        return emptyList()
    }

    fun activate(profileMap: Map<*, *>) {
        val profile = parseProfile(profileMap)
        if (!checkRoot()) {
            setError("Root not available (su denied).")
            return
        }
        if (!checkSupport()) {
            setError("USB gadget support not detected (configfs/UDC missing).")
            return
        }

        setState("ACTIVATING", profile.id, "Creating gadget…")

        // Crucial: close any open persistent writers in root shell before re-binding or recreating
        closeHidWritersBestEffort()

        val snap = captureUsbSnapshot()
        prefs.setUsbSnapshot(
            sysUsbConfig = snap.sysUsbConfig,
            sysUsbState = snap.sysUsbState,
            sysUsbConfigfs = snap.sysUsbConfigfs,
            persistSysUsbConfig = snap.persistSysUsbConfig,
            boundGadgets = snap.boundGadgetsRaw,
        )

        val gadgetDir = "gadgetfs_${profile.id.take(12).lowercase(Locale.US)}"

        val checkReuseScript = """
            CFGBASE="/config/usb_gadget"
            [ -d "${'$'}CFGBASE" ] || CFGBASE="/sys/kernel/config/usb_gadget"
            G="${'$'}CFGBASE/$gadgetDir"
            [ -d "${'$'}G" ] || exit 1
            [ -d "${'$'}G/functions/hid.usb0" ] || exit 1
            ${if (profile.roleType.lowercase(Locale.US) == "composite") "[ -d \"${'$'}G/functions/hid.usb1\" ] || exit 1" else ""}

            UDC_NAME=${'$'}(getprop sys.usb.controller 2>/dev/null | tr -d '\r')
            [ -z "${'$'}UDC_NAME" ] && UDC_NAME=${'$'}(ls -1 /sys/class/udc 2>/dev/null | head -n1 | tr -d '\r')
            [ -z "${'$'}UDC_NAME" ] && exit 2

            for U in "${'$'}CFGBASE"/*/UDC; do
              [ -f "${'$'}U" ] || continue
              [ "${'$'}U" = "${'$'}G/UDC" ] && continue
              cur=${'$'}(cat "${'$'}U" 2>/dev/null | tr -d '\r')
              [ "${'$'}cur" = "${'$'}UDC_NAME" ] && echo "" > "${'$'}U" 2>/dev/null || true
            done

            echo "${'$'}UDC_NAME" > "${'$'}G/UDC" 2>/dev/null || true
            udc=${'$'}(cat "${'$'}G/UDC" 2>/dev/null | tr -d '\r\n')
            [ -n "${'$'}udc" ] || exit 3

            for fn in "${'$'}G"/functions/hid.*; do
              [ -d "${'$'}fn" ] || continue
              if [ -f "${'$'}fn/dev" ]; then
                devpair=${'$'}(cat "${'$'}fn/dev" 2>/dev/null | tr -d '\r')
                maj=${'$'}{devpair%:*}
                min=${'$'}{devpair#*:}
                node="/dev/hidg${'$'}min"
                if [ ! -c "${'$'}node" ] && [ -n "${'$'}maj" ] && [ -n "${'$'}min" ]; then
                  rm -f "${'$'}node" 2>/dev/null || true
                  mknod "${'$'}node" c "${'$'}maj" "${'$'}min" 2>/dev/null || true
                fi
                chmod 666 "${'$'}node" 2>/dev/null || true
              fi
            done
            chmod 666 /dev/hidg* 2>/dev/null || true
            exit 0
        """.trimIndent()

        val reuseRes = root.exec(checkReuseScript, timeoutSec = 10)
        val ready = if (reuseRes.ok) {
            log.log("gadget", "Re-bound existing gadget directory: $gadgetDir")
            true
        } else {
            val script = Configfs.buildCreateAndBindScript(profile, gadgetDir)
            val r = root.exec(script, timeoutSec = 30)
            if (!r.ok) {
                log.logError("gadget", "Activation failed; attempting USB restore")
                restoreUsbSnapshotBestEffort(reason = "activation_failed")
                prefs.clearUsbSnapshot()
                setError("Activation failed (exit=${r.exitCode}). ${r.stderr.trim().ifEmpty { r.stdout.trim() }}")
                false
            } else {
                true
            }
        }

        if (!ready) return

        fun findHidDev(gDir: String, fnName: String, fallback: String): String {
            val s = "cat /config/usb_gadget/$gDir/functions/$fnName/dev 2>/dev/null || cat /sys/kernel/config/usb_gadget/$gDir/functions/$fnName/dev 2>/dev/null"
            val out = root.exec(s).stdout.trim()
            val minor = out.substringAfter(':', "").trim()
            return if (minor.isNotEmpty()) "/dev/hidg$minor" else fallback
        }

        val kbdDev = when (profile.roleType.lowercase(Locale.US)) {
            "mouse" -> null
            "keyboard" -> findHidDev(gadgetDir, "hid.usb0", "/dev/hidg1")
            else -> findHidDev(gadgetDir, "hid.usb0", "/dev/hidg1") // composite: hid.usb0 is keyboard
        }
        val mouseDev = when (profile.roleType.lowercase(Locale.US)) {
            "mouse" -> findHidDev(gadgetDir, "hid.usb0", "/dev/hidg1")
            "keyboard" -> null
            else -> findHidDev(gadgetDir, "hid.usb1", "/dev/hidg2") // composite: hid.usb1 is mouse
        }

        inMemoryKbdDev = kbdDev
        inMemoryMouseDev = mouseDev
        prefs.setActive(profile.id, profile.roleType, gadgetDir, kbdDev, mouseDev)
        startForeground("USB gadget active: ${profile.name}")

        // Critical: open persistent writers (FD 3/4) in the long-lived root session.
        openHidWritersBestEffort(kbdDev, mouseDev)

        setState("ACTIVE", profile.id, null)
        log.log("gadget", "Active profile: ${profile.id} (${profile.roleType})")
    }

    fun deactivate() {
        val current = statusRef.get()
        if (current.state == "IDLE") return
        if (current.state == "ACTIVATING") return

        setState("ACTIVATING", current.activeProfileId, "Deactivating…")

        try {
            // Keep writers open while releasing keys.
            releaseAllKeysBestEffort()
        } catch (_: Throwable) {
        }

        // Now close persistent writers before unbinding (best-effort).
        closeHidWritersBestEffort()

        val gadgetDir = prefs.activeGadgetDir
        if (!gadgetDir.isNullOrBlank()) {
            root.exec(Configfs.buildUnbindAndCleanupScript(gadgetDir), timeoutSec = 20)
        } else {
            root.exec(Configfs.buildPanicStopScript(), timeoutSec = 20)
        }

        stopForeground()
        restoreUsbSnapshotBestEffort(reason = "deactivate")
        inMemoryKbdDev = null
        inMemoryMouseDev = null
        prefs.clearActive()
        prefs.clearUsbSnapshot()

        setState("IDLE", null, null)
        log.log("gadget", "Deactivated")
    }

    fun panicStop() {
        setState("ACTIVATING", null, "Panic stop…")

        try {
            // Keep writers open while releasing keys.
            releaseAllKeysBestEffort()
        } catch (_: Throwable) {
        }

        // Close persistent writers best-effort.
        closeHidWritersBestEffort()

        val gadgetDir = prefs.activeGadgetDir
        if (!gadgetDir.isNullOrBlank()) {
            root.exec(Configfs.buildUnbindAndCleanupScript(gadgetDir), timeoutSec = 20)
        } else {
            root.exec(Configfs.buildPanicStopScript(), timeoutSec = 20)
        }

        stopForeground()
        restoreUsbSnapshotBestEffort(reason = "panic_stop")
        inMemoryKbdDev = null
        inMemoryMouseDev = null
        prefs.clearActive()
        prefs.clearUsbSnapshot()

        setState("IDLE", null, null)
        log.log("gadget", "Panic stop complete")
    }

    fun testMouseMove(dx: Int, dy: Int, wheel: Int, buttons: Int) {
        val current = statusRef.get()
        if (current.state != "ACTIVE") {
            if (!discoverAndRecoverActiveGadget()) {
                throw IllegalStateException("Gadget is not active")
            }
            refreshAndEmitStatus(restoreFromPrefs = true)
        }
        var path = inMemoryMouseDev ?: prefs.activeMouseDev
        if (path.isNullOrBlank()) {
            discoverAndRecoverActiveGadget()
            path = inMemoryMouseDev ?: prefs.activeMouseDev
        }
        if (path.isNullOrBlank()) throw IllegalStateException("Mouse HID device not available")

        if (!root.isMouseWriterReady()) {
            val now = System.currentTimeMillis()
            if (now - lastWriterAttemptMs > 4000L) {
                lastWriterAttemptMs = now
                openHidWritersBestEffort(inMemoryKbdDev ?: prefs.activeKeyboardDev, path)
            }
        }

        val report = byteArrayOf(
            (buttons and 0xFF).toByte(),
            (dx.coerceIn(-127, 127) and 0xFF).toByte(),
            (dy.coerceIn(-127, 127) and 0xFF).toByte(),
            (wheel.coerceIn(-127, 127) and 0xFF).toByte(),
        )

        writeMouseReport(path, report)
        if (buttons != lastLoggedButtons) {
            lastLoggedButtons = buttons
            log.log("test", "Mouse buttons changed to $buttons at $path")
        } else if (dx != 0 || dy != 0 || wheel != 0) {
            val now = System.currentTimeMillis()
            if (now - lastMouseMoveLogTime > 3000L) {
                lastMouseMoveLogTime = now
                log.log("test", "Mouse active -> $path (dx=$dx dy=$dy wheel=$wheel)")
            }
        }
    }

    /**
     * Backward-compatible API called by Flutter for both:
     * - single key (ENTER, A, BACKSPACE, etc)
     * - typed text batches (e.g. "hello world")
     *
     * Rule:
     * - If keyLabel resolves to a known key -> send one tap.
     * - Else -> treat as text, type it (with chunking).
     */
    fun testKeyboardKey(keyLabel: String) {
        val current = statusRef.get()
        if (current.state != "ACTIVE") {
            if (!discoverAndRecoverActiveGadget()) {
                throw IllegalStateException("Gadget is not active")
            }
            refreshAndEmitStatus(restoreFromPrefs = true)
        }
        var path = inMemoryKbdDev ?: prefs.activeKeyboardDev
        if (path.isNullOrBlank()) {
            discoverAndRecoverActiveGadget()
            path = inMemoryKbdDev ?: prefs.activeKeyboardDev
        }
        if (path.isNullOrBlank()) throw IllegalStateException("Keyboard HID device not available")

        if (!root.isKeyboardWriterReady()) {
            val now = System.currentTimeMillis()
            if (now - lastWriterAttemptMs > 4000L) {
                lastWriterAttemptMs = now
                openHidWritersBestEffort(path, inMemoryMouseDev ?: prefs.activeMouseDev)
            }
        }

        val trimmed = keyLabel.trimEnd('\r')
        if (trimmed.isEmpty()) return

        val code = HidSpec.keyCodeFor(trimmed)
        if (code != null) {
            // Single key tap
            writeKeyboardTap(path, mods = 0x00, key = code, downHoldUs = keyDownHoldUs)
            log.log("test", "Keyboard key=$trimmed code=0x${Integer.toHexString(code)}")
            return
        }

        // Otherwise treat as text (batch typing)
        typeText(path, trimmed)
        val preview = if (trimmed.length <= 18) trimmed else trimmed.take(18) + "…"
        log.log("test", "Keyboard text(len=${trimmed.length}) \"$preview\"")
    }

    fun testCtrlAltDel() {
        val current = statusRef.get()
        if (current.state != "ACTIVE") {
            if (!discoverAndRecoverActiveGadget()) {
                throw IllegalStateException("Gadget is not active")
            }
            refreshAndEmitStatus(restoreFromPrefs = true)
        }
        var path = inMemoryKbdDev ?: prefs.activeKeyboardDev
        if (path.isNullOrBlank()) {
            discoverAndRecoverActiveGadget()
            path = inMemoryKbdDev ?: prefs.activeKeyboardDev
        }
        if (path.isNullOrBlank()) throw IllegalStateException("Keyboard HID device not available")

        if (!root.isKeyboardWriterReady()) {
            val now = System.currentTimeMillis()
            if (now - lastWriterAttemptMs > 4000L) {
                lastWriterAttemptMs = now
                openHidWritersBestEffort(path, inMemoryMouseDev ?: prefs.activeMouseDev)
            }
        }

        val mods = 0x01 or 0x04 // left-ctrl + left-alt
        val del = HidSpec.keyCodeFor("DELETE") ?: 0x4C
        writeKeyboardTap(path, mods = mods, key = del, downHoldUs = 12000)
        log.log("test", "Ctrl+Alt+Del sent")
    }

    private fun openHidWritersBestEffort(kbdDev: String?, mouseDev: String?) {
        try {
            root.exec("chmod 666 /dev/hidg* 2>/dev/null || true", timeoutSec = 3)
            val rr = root.openHidWriters(kbdDev, mouseDev, timeoutSec = 6)
            if (rr.ok) {
                log.log(
                    "hid",
                    "Persistent HID writers ready: kbd=${root.isKeyboardWriterReady()} mouse=${root.isMouseWriterReady()}"
                )
            } else {
                log.logError(
                    "hid",
                    "Failed to open persistent HID writers (exit=${rr.exitCode}). Falling back to per-write opens."
                )
            }
        } catch (t: Throwable) {
            log.logError("hid", "openHidWriters failed: ${t.message}")
        }
    }

    private fun reopenHidWritersFromPrefsBestEffort() {
        val kbdDev = inMemoryKbdDev ?: prefs.activeKeyboardDev
        val mouseDev = inMemoryMouseDev ?: prefs.activeMouseDev
        if (kbdDev.isNullOrBlank() && mouseDev.isNullOrBlank()) return
        openHidWritersBestEffort(kbdDev, mouseDev)
    }

    private fun closeHidWritersBestEffort() {
        try {
            root.closeHidWriters(timeoutSec = 4)
        } catch (_: Throwable) {
        }
    }

    private fun parseProfile(map: Map<*, *>): Configfs.ParsedProfile {
        val id = (map["id"] ?: "").toString().ifBlank { throw IllegalArgumentException("Profile id missing") }
        val name = (map["name"] ?: "Profile").toString()
        val roleType = (map["roleType"] ?: "mouse").toString()
        val tunables = (map["tunables"] as? Map<*, *>)

        fun str(key: String, fallback: String): String {
            val v = (tunables?.get(key) ?: map[key])?.toString()
            return if (v.isNullOrBlank()) fallback else v
        }

        fun intHexOrDec(key: String, fallback: Int): Int {
            val raw = (tunables?.get(key) ?: map[key])?.toString()?.trim()
            if (raw.isNullOrBlank()) return fallback
            return try {
                if (raw.startsWith("0x", ignoreCase = true)) raw.substring(2).toInt(16) else raw.toInt()
            } catch (_: Throwable) {
                fallback
            }
        }

        val manufacturer = str("manufacturer", "KaijinLab")
        val product = str("product", "GadgetFS")
        val serial = str("serialNumber", "GadgetFS:${id.take(12)}")
        val vendorId = intHexOrDec("vendorId", 0x1d6b)
        val productId = intHexOrDec(
            "productId",
            when (roleType.lowercase(Locale.US)) {
                "keyboard" -> 0x0104
                "mouse" -> 0x0104
                else -> 0x0104
            }
        )
        val maxPower = intHexOrDec("maxPowerMa", 250)

        return Configfs.ParsedProfile(
            id = id,
            name = name,
            roleType = roleType,
            manufacturer = manufacturer,
            product = product,
            serialNumber = serial,
            vendorId = vendorId,
            productId = productId,
            maxPowerMa = maxPower,
        )
    }

    private fun keyboardReport(mods: Int, key: Int): ByteArray {
        return byteArrayOf(
            (mods and 0xFF).toByte(),
            0x00,
            (key and 0xFF).toByte(),
            0x00, 0x00, 0x00, 0x00, 0x00
        )
    }

    private fun releaseAllKeysBestEffort() {
        val path = inMemoryKbdDev ?: prefs.activeKeyboardDev ?: return
        val up = keyboardReport(0x00, 0x00)
        try {
            if (root.isKeyboardWriterReady()) {
                root.writeKeyboardFast(up)
            } else {
                writeKeyboardReportsWithDelays(
                    path,
                    reports = listOf(up),
                    delaysUs = emptyList()
                )
            }
            log.log("kbd", "Sent all-keys-up before teardown")
        } catch (t: Throwable) {
            log.logError("kbd", "Failed to send all-keys-up: ${t.message}")
        }
    }

    private fun writeKeyboardTap(path: String, mods: Int, key: Int, downHoldUs: Int) {
        val up = keyboardReport(0x00, 0x00)
        val down = keyboardReport(mods, key)

        // Fast path: if keyboard writer is ready in persistent session, write directly!
        if (root.isKeyboardWriterReady()) {
            try {
                root.writeKeyboardFast(down)
                val holdMs = max(1L, (downHoldUs / 1000).toLong())
                Thread.sleep(holdMs)
                root.writeKeyboardFast(up)
                return
            } catch (t: Throwable) {
                log.logError("kbd", "Fast keyboard tap failed, falling back: ${t.message}")
            }
        }

        // Sequence: up -> down -> (hold) -> up
        writeKeyboardReportsWithDelays(
            path,
            reports = listOf(up, down, up),
            delaysUs = listOf(interKeyDelayUs, downHoldUs)
        )
    }

    private fun typeText(path: String, text: String) {
        var idx = 0
        while (idx < text.length) {
            val end = min(text.length, idx + maxTypedCharsPerBatch)
            val chunk = text.substring(idx, end)
            typeTextChunk(path, chunk)
            idx = end
        }
    }

    private fun typeTextChunk(path: String, chunk: String) {
        val strokes = ArrayList<HidSpec.KeyStroke>(chunk.length)
        for (ch in chunk) {
            val s = HidSpec.strokeForChar(ch)
            if (s != null) {
                strokes.add(s)
            } else {
                val c = if (ch.code in 32..126) ch.toString() else "U+${ch.code.toString(16)}"
                log.log("kbd", "Skipping unsupported char: $c")
            }
        }
        if (strokes.isEmpty()) return

        val reports = ArrayList<ByteArray>(1 + strokes.size * 2)
        val delays = ArrayList<Int>(strokes.size * 2)

        // Start from "all keys up"
        reports.add(keyboardReport(0x00, 0x00))

        // Then for each keystroke: DOWN -> UP
        for (stroke in strokes) {
            reports.add(keyboardReport(stroke.mods, stroke.key))
            reports.add(keyboardReport(0x00, 0x00))
        }

        // Delay list is (reports.size - 1)
        for (i in 0 until (reports.size - 1)) {
            val isDownReport = (i % 2 == 1) // 1,3,5... are DOWN
            delays.add(if (isDownReport) keyDownHoldUs else interKeyDelayUs)
        }

        writeKeyboardReportsWithDelays(path, reports, delays)
    }

    /**
     * Writes multiple HID keyboard reports.
     * - Fast path: writes reports directly into persistent FD 3 if ready.
     * - Robust fallback: executes compound redirection block { ... } > "$P"
     *   which opens "$P" once and NEVER relies on FD 3 or fails with bad file descriptor.
     */
    private fun writeKeyboardReportsWithDelays(path: String, reports: List<ByteArray>, delaysUs: List<Int>) {
        if (reports.isEmpty()) return

        // 1. Fast Path: write reports directly via persistent writer
        if (root.isKeyboardWriterReady()) {
            try {
                for (i in reports.indices) {
                    root.writeKeyboardFast(reports[i])
                    if (i != reports.lastIndex) {
                        val dUs = delaysUs.getOrNull(i) ?: 0
                        if (dUs > 0) {
                            val ms = (dUs / 1000).toLong()
                            val ns = ((dUs % 1000) * 1000)
                            if (ms > 0 || ns > 0) {
                                Thread.sleep(ms, ns)
                            }
                        }
                    }
                }
                return
            } catch (t: Throwable) {
                log.logError("kbd", "Keyboard fast-writer multi-report failed; falling back to compound script: ${t.message}")
            }
        }

        // 2. Robust Fallback: POSIX compound redirection block { ... } > "$P"
        val usleepSnippet = """
          USLP=""
          if command -v toybox >/dev/null 2>&1 && toybox usleep 1 >/dev/null 2>&1; then
            USLP="toybox usleep"
          elif command -v usleep >/dev/null 2>&1; then
            USLP="usleep"
          elif command -v busybox >/dev/null 2>&1 && busybox usleep 1 >/dev/null 2>&1; then
            USLP="busybox usleep"
          fi
        """.trimIndent()

        fun toHexEsc(bytes: ByteArray): String {
            return bytes.joinToString(separator = "") { b ->
                val v = b.toInt() and 0xFF
                String.format(Locale.US, "\\x%02x", v)
            }
        }

        val writes = StringBuilder()
        for (i in reports.indices) {
            val hex = toHexEsc(reports[i])
            writes.append("printf '%b' '").append(hex).append("'\n")
            if (i != reports.lastIndex) {
                val d = delaysUs.getOrNull(i) ?: 0
                if (d > 0) {
                    writes.append(
                        """
                          if [ -n "${'$'}USLP" ]; then
                            ${'$'}USLP $d
                          else
                            sleep 0.01
                          fi
                        """.trimIndent()
                    ).append("\n")
                }
            }
        }

        val script = """
          set -e
          P=${shQuote(path)}
          $usleepSnippet

          {
          $writes
          } > "${'$'}P"
        """.trimIndent()

        val r = root.exec(script, timeoutSec = 8)
        if (!r.ok) {
          val detail = r.stderr.trim().ifEmpty { r.stdout.trim() }
          throw IllegalStateException(
            "Failed to write keyboard reports to $path (exit=${r.exitCode}). " +
              (detail.ifEmpty { "no stderr/stdout" })
          )
        }
    }

    /**
     * Mouse report write:
     * - Fast path: persistent FD 4 (no exec, no markers, no open/close)
     * - Fallback: one-shot redirection to path
     */
    private fun writeMouseReport(path: String, bytes: ByteArray) {
        if (root.isMouseWriterReady()) {
            try {
                root.writeMouseFast(bytes)
                return
            } catch (t: Throwable) {
                log.logError("hid", "Mouse fast-writer failed; fallback to slow path: ${t.message}")
            }
        }

        // Slow fallback: open/write/close within one exec
        val hexEsc = bytes.joinToString(separator = "") { b ->
            val v = b.toInt() and 0xFF
            String.format(Locale.US, "\\x%02x", v)
        }
        val script = "printf '%b' '$hexEsc' > ${shQuote(path)}"
        val r = root.exec(script, timeoutSec = 5)
        if (!r.ok) {
            throw IllegalStateException("Failed to write HID report to $path (exit=${r.exitCode})")
        }
    }

    private fun shQuote(s: String): String = "'" + s.replace("'", "'\\''") + "'"

    /**
     * Returns true if configfs USB gadget is available.
     *
     * On many Android devices configfs is mounted at /config (not /sys/kernel/config).
     * Some ROMs do not mount configfs automatically; we try a best-effort mount.
     */
    private fun ensureConfigfsAvailable(): Boolean {
        val fast = root.exec("test -d /config/usb_gadget || test -d /sys/kernel/config/usb_gadget")
        if (fast.ok) return true

        val script = """
            if [ -d /config ] && [ ! -d /config/usb_gadget ]; then
              mount | grep -q " /config " || mount -t configfs none /config 2>/dev/null
            fi
            if [ -d /sys/kernel ] && [ ! -d /sys/kernel/config/usb_gadget ]; then
              mkdir -p /sys/kernel/config 2>/dev/null
              mount | grep -q " /sys/kernel/config " || mount -t configfs none /sys/kernel/config 2>/dev/null
            fi
            test -d /config/usb_gadget || test -d /sys/kernel/config/usb_gadget
        """.trimIndent()

        val mounted = root.exec(script, timeoutSec = 10)
        return mounted.ok
    }

    private fun isGadgetDirBound(gadgetDir: String): Boolean {
        val safe = gadgetDir.replace("\"", "").replace("'", "")
        val script = """
            CFGBASE=/config/usb_gadget
            [ -d "${'$'}CFGBASE" ] || CFGBASE=/sys/kernel/config/usb_gadget
            if [ -f "${'$'}CFGBASE/$safe/UDC" ]; then
              udc=${'$'}(cat "${'$'}CFGBASE/$safe/UDC" 2>/dev/null | tr -d '\r\n')
              [ -n "${'$'}udc" ]
            else
              exit 1
            fi
        """.trimIndent()
        val r = root.exec(script, timeoutSec = 5)
        return r.ok
    }

    private fun discoverAndRecoverActiveGadget(): Boolean {
        if (!checkRoot()) return false
        if (!ensureConfigfsAvailable()) return false

        val savedDir = prefs.activeGadgetDir ?: ""
        val safeSaved = savedDir.replace("\"", "").replace("'", "")

        val script = """
            CFGBASE="/config/usb_gadget"
            if [ ! -d "${'$'}CFGBASE" ]; then
              CFGBASE="/sys/kernel/config/usb_gadget"
            fi
            if [ ! -d "${'$'}CFGBASE" ]; then
              exit 1
            fi

            TARGET=""
            CHECK_DIR=${shQuote(safeSaved)}
            if [ -n "${'$'}CHECK_DIR" ] && [ -d "${'$'}CFGBASE/${'$'}CHECK_DIR" ]; then
              TARGET="${'$'}CHECK_DIR"
            fi

            if [ -z "${'$'}TARGET" ]; then
              for g in "${'$'}CFGBASE"/gadgetfs*; do
                [ -d "${'$'}g" ] || continue
                TARGET=${'$'}(basename "${'$'}g")
                break
              done
            fi

            if [ -z "${'$'}TARGET" ]; then
              exit 1
            fi

            GDIR="${'$'}CFGBASE/${'$'}TARGET"
            echo "GADGET_DIR=${'$'}TARGET"

            # Check if UDC is bound; if not, bind to the available controller
            udc=${'$'}(cat "${'$'}GDIR/UDC" 2>/dev/null | tr -d '\r\n')
            if [ -z "${'$'}udc" ]; then
              UDC_NAME=${'$'}(getprop sys.usb.controller 2>/dev/null | tr -d '\r')
              if [ -z "${'$'}UDC_NAME" ]; then
                UDC_NAME=${'$'}(ls -1 /sys/class/udc 2>/dev/null | head -n 1 | tr -d '\r')
              fi
              if [ -n "${'$'}UDC_NAME" ]; then
                for other in "${'$'}CFGBASE"/*; do
                  [ -d "${'$'}other" ] || continue
                  [ "${'$'}other" = "${'$'}GDIR" ] && continue
                  if [ -f "${'$'}other/UDC" ]; then
                    cur_u=${'$'}(cat "${'$'}other/UDC" 2>/dev/null | tr -d '\r')
                    if [ "${'$'}cur_u" = "${'$'}UDC_NAME" ]; then
                      echo "" > "${'$'}other/UDC" 2>/dev/null || true
                    fi
                  fi
                done
                echo "${'$'}UDC_NAME" > "${'$'}GDIR/UDC" 2>/dev/null || true
              fi
            fi

            if [ -f "${'$'}GDIR/strings/0x409/serialnumber" ]; then
              sn=${'$'}(cat "${'$'}GDIR/strings/0x409/serialnumber" 2>/dev/null | tr -d '\r\n')
              echo "SERIAL=${'$'}sn"
            fi

            for fn in "${'$'}GDIR"/functions/hid.*; do
              [ -d "${'$'}fn" ] || continue
              fname=${'$'}(basename "${'$'}fn")
              proto=""
              rlen=""
              if [ -f "${'$'}fn/protocol" ]; then
                proto=${'$'}(cat "${'$'}fn/protocol" 2>/dev/null | tr -d '\r\n')
              fi
              if [ -f "${'$'}fn/report_length" ]; then
                rlen=${'$'}(cat "${'$'}fn/report_length" 2>/dev/null | tr -d '\r\n')
              fi
              if [ -f "${'$'}fn/dev" ]; then
                devpair=${'$'}(cat "${'$'}fn/dev" 2>/dev/null | tr -d '\r\n')
                maj=${'$'}{devpair%:*}
                min=${'$'}{devpair#*:}
                node="/dev/hidg${'$'}min"
                if [ ! -c "${'$'}node" ] && [ -n "${'$'}maj" ] && [ -n "${'$'}min" ]; then
                  rm -f "${'$'}node" 2>/dev/null || true
                  mknod "${'$'}node" c "${'$'}maj" "${'$'}min" 2>/dev/null || true
                fi
                chmod 666 "${'$'}node" 2>/dev/null || true
                echo "HID_FN=${'$'}fname:node=${'$'}node:proto=${'$'}proto:rlen=${'$'}rlen"
              fi
            done
            chmod 666 /dev/hidg* 2>/dev/null || true
            exit 0
        """.trimIndent()

        val r = root.exec(script, timeoutSec = 8)
        if (!r.ok) {
            return false
        }

        var foundDir: String? = null
        var foundSerial: String? = null
        data class FnInfo(val name: String, val node: String, val proto: String, val rlen: String)
        val hidFunctions = ArrayList<FnInfo>()

        for (line in r.stdout.lineSequence()) {
            val t = line.trim()
            if (t.startsWith("GADGET_DIR=")) {
                foundDir = t.removePrefix("GADGET_DIR=").trim()
            } else if (t.startsWith("SERIAL=")) {
                foundSerial = t.removePrefix("SERIAL=").trim()
            } else if (t.startsWith("HID_FN=")) {
                val parts = t.removePrefix("HID_FN=").split(':')
                val fname = parts.getOrNull(0) ?: ""
                var node = ""
                var proto = ""
                var rlen = ""
                for (part in parts.drop(1)) {
                    if (part.startsWith("node=")) node = part.removePrefix("node=")
                    if (part.startsWith("proto=")) proto = part.removePrefix("proto=")
                    if (part.startsWith("rlen=")) rlen = part.removePrefix("rlen=")
                }
                if (node.isNotEmpty()) {
                    hidFunctions.add(FnInfo(fname, node, proto, rlen))
                }
            }
        }

        if (foundDir.isNullOrBlank()) return false

        val savedId = prefs.activeProfileId
        val resolvedProfileId = when {
            !savedId.isNullOrBlank() -> savedId
            !foundSerial.isNullOrBlank() && foundSerial.startsWith("GadgetFS:") -> foundSerial.removePrefix("GadgetFS:")
            else -> foundDir.removePrefix("gadgetfs_")
        }

        var kbdDev: String? = null
        var mouseDev: String? = null

        for (fn in hidFunctions) {
            if (fn.proto == "1" || fn.rlen == "8") {
                kbdDev = fn.node
            } else if (fn.proto == "2" || fn.rlen == "4") {
                mouseDev = fn.node
            } else if (fn.name == "hid.usb0" && hidFunctions.size > 1) {
                kbdDev = fn.node
            } else if (fn.name == "hid.usb1") {
                mouseDev = fn.node
            }
        }

        if (hidFunctions.size == 1) {
            val single = hidFunctions[0]
            val savedRole = prefs.activeRoleType?.lowercase(Locale.US)
            if (kbdDev == null && mouseDev == null) {
                if (savedRole == "mouse") {
                    mouseDev = single.node
                } else {
                    kbdDev = single.node
                }
            }
        }

        if (kbdDev == null) kbdDev = prefs.activeKeyboardDev?.takeIf { root.exec("test -c $it").ok }
        if (mouseDev == null) mouseDev = prefs.activeMouseDev?.takeIf { root.exec("test -c $it").ok }

        val resolvedRoleType = when {
            kbdDev != null && mouseDev != null -> "composite"
            mouseDev != null -> "mouse"
            kbdDev != null -> "keyboard"
            else -> prefs.activeRoleType ?: "mouse"
        }

        inMemoryKbdDev = kbdDev
        inMemoryMouseDev = mouseDev

        prefs.setActive(resolvedProfileId, resolvedRoleType, foundDir, kbdDev, mouseDev)
        openHidWritersBestEffort(kbdDev, mouseDev)
        startForeground("USB gadget active: $resolvedRoleType")

        log.log("gadget", "Recovered active gadget: dir=$foundDir profile=$resolvedProfileId role=$resolvedRoleType kbd=$kbdDev mouse=$mouseDev")
        return true
    }

    private fun startForeground(title: String) {
        try {
            val intent = Intent(context, GadgetForegroundService::class.java).apply {
                putExtra(GadgetForegroundService.EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        } catch (t: Throwable) {
            log.logError("gadget", "startForeground failed: ${t.message}")
        }
    }

    private fun stopForeground() {
        try {
            context.stopService(Intent(context, GadgetForegroundService::class.java))
        } catch (_: Throwable) {
        }
    }

    private fun setState(state: String, activeProfileId: String?, message: String?) {
        val current = statusRef.get()
        val next = current.copy(state = state, activeProfileId = activeProfileId, message = message)
        statusRef.set(next)
        emit(next)
    }

    private fun setError(message: String) {
        val current = statusRef.get()
        val next = current.copy(state = "ERROR", message = message)
        statusRef.set(next)
        emit(next)
        log.logError("gadget", message)
    }

    private data class UsbSnapshot(
        val sysUsbConfig: String?,
        val sysUsbState: String?,
        val sysUsbConfigfs: String?,
        val persistSysUsbConfig: String?,
        val boundGadgetsRaw: String?,
    )

    private fun captureUsbSnapshot(): UsbSnapshot {
        fun getProp(name: String): String? {
            val r = root.exec("getprop $name 2>/dev/null || true", timeoutSec = 5)
            val v = r.stdout.lineSequence().firstOrNull()?.trim()?.trim('\r')
            return v?.takeIf { it.isNotBlank() }
        }

        val bound = root.exec(buildListBoundGadgetsScript(), timeoutSec = 8).stdout
            .lineSequence()
            .map { it.trim().trim('\r') }
            .filter { it.isNotBlank() }
            .joinToString("\n")
            .ifBlank { null }

        val snap = UsbSnapshot(
            sysUsbConfig = getProp("sys.usb.config"),
            sysUsbState = getProp("sys.usb.state"),
            sysUsbConfigfs = getProp("sys.usb.configfs"),
            persistSysUsbConfig = getProp("persist.sys.usb.config"),
            boundGadgetsRaw = bound,
        )

        log.log(
            "usb",
            "Snapshot sys.usb.config=${snap.sysUsbConfig ?: "?"} sys.usb.state=${snap.sysUsbState ?: "?"} " +
                "sys.usb.configfs=${snap.sysUsbConfigfs ?: "?"} persist.sys.usb.config=${snap.persistSysUsbConfig ?: "?"} " +
                "bound=${if (snap.boundGadgetsRaw.isNullOrBlank()) "none" else "yes"}"
        )
        return snap
    }

    private fun buildListBoundGadgetsScript(): String {
        return """
            CFGBASE="/config/usb_gadget"
            if [ ! -d "${'$'}CFGBASE" ]; then
              CFGBASE="/sys/kernel/config/usb_gadget"
            fi
            if [ ! -d "${'$'}CFGBASE" ]; then
              exit 0
            fi
            for g in "${'$'}CFGBASE"/*; do
              [ -d "${'$'}g" ] || continue
              if [ -f "${'$'}g/UDC" ]; then
                udc=${'$'}(cat "${'$'}g/UDC" 2>/dev/null | tr -d '\r')
                if [ -n "${'$'}udc" ]; then
                  echo "${'$'}(basename "${'$'}g"):${'$'}udc"
                fi
              fi
            done
            exit 0
        """.trimIndent()
    }

    private fun restoreUsbSnapshotBestEffort(reason: String) {
        val prevConfig = prefs.prevSysUsbConfig?.trim()?.takeIf { it.isNotEmpty() }
        val prevConfigfs = prefs.prevSysUsbConfigfs?.trim()?.takeIf { it.isNotEmpty() }
        val prevPersist = prefs.prevPersistSysUsbConfig?.trim()?.takeIf { it.isNotEmpty() }
        val prevBound = prefs.prevBoundGadgets?.trim()?.takeIf { it.isNotEmpty() }

        if (prevConfig == null && prevConfigfs == null && prevPersist == null && prevBound == null) {
            log.log("usb", "No snapshot to restore ($reason)")
            return
        }

        log.log("usb", "Restoring USB snapshot ($reason) prevConfig=${prevConfig ?: "?"}")
        val script = buildRestoreUsbScript(prevConfig, prevConfigfs, prevPersist, prevBound)
        val r = root.exec(script, timeoutSec = 20)
        if (!r.ok) {
            log.logError("usb", "USB restore script returned exit=${r.exitCode}")
        } else {
            log.log("usb", "USB restore script completed")
        }
    }

    private fun buildRestoreUsbScript(
        prevConfig: String?,
        prevConfigfs: String?,
        prevPersist: String?,
        prevBoundRaw: String?
    ): String {
        val cfg = prevConfig ?: ""
        val cfgfs = prevConfigfs ?: ""
        val pcfg = prevPersist ?: ""

        val boundLines = (prevBoundRaw ?: "")
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()

        val rebindBlock = if (boundLines.isNotEmpty()) {
            val entries = boundLines.joinToString("\n") { it }
            """
            CFGBASE="/config/usb_gadget"
            if [ ! -d "${'$'}CFGBASE" ]; then
              CFGBASE="/sys/kernel/config/usb_gadget"
            fi
            if [ -d "${'$'}CFGBASE" ]; then
              while IFS= read -r line; do
                g=${'$'}(echo "${'$'}line" | cut -d: -f1)
                u=${'$'}(echo "${'$'}line" | cut -d: -f2-)
                if [ -n "${'$'}g" ] && [ -n "${'$'}u" ] && [ -f "${'$'}CFGBASE/${'$'}g/UDC" ]; then
                  (echo "${'$'}u" > "${'$'}CFGBASE/${'$'}g/UDC") 2>/dev/null || true
                fi
              done <<'EOF_BOUND'
            $entries
            EOF_BOUND
            fi
            """.trimIndent()
        } else {
            "true"
        }

        return """
            set -e

            PREV_CFG=${shQuote(cfg)}
            PREV_CFGFS=${shQuote(cfgfs)}
            PREV_PERSIST=${shQuote(pcfg)}

            if [ -n "${'$'}PREV_CFGFS" ]; then
              setprop sys.usb.configfs "${'$'}PREV_CFGFS" 2>/dev/null || true
            fi

            if [ -n "${'$'}PREV_PERSIST" ]; then
              setprop persist.sys.usb.config "${'$'}PREV_PERSIST" 2>/dev/null || true
            fi

            if [ -n "${'$'}PREV_CFG" ]; then
              setprop sys.usb.config none 2>/dev/null || true
              sleep 0.1
              setprop sys.usb.config "${'$'}PREV_CFG" 2>/dev/null || true

              i=0
              while [ ${'$'}i -lt 80 ]; do
                cur=${'$'}(getprop sys.usb.state 2>/dev/null | tr -d '\r')
                if [ "${'$'}cur" = "${'$'}PREV_CFG" ]; then
                  break
                fi
                sleep 0.1
                i=${'$'}((i+1))
              done
            fi

            $rebindBlock

            exit 0
        """.trimIndent()
    }

    /* ---- Kernel config diagnostics (unchanged) ---- */

    private fun kernelVersionBase(unameR: String): String {
        val trimmed = unameR.trim()
        if (trimmed.isEmpty()) return "Unknown"
        val first = trimmed.split(Regex("[\\s\\-\\+]")).firstOrNull()?.trim()
        return first?.takeIf { it.isNotEmpty() } ?: trimmed
    }

    private fun readKernelUnameR(): String? {
        val r = root.exec("uname -r 2>/dev/null || true", timeoutSec = 5)
        val v = r.stdout.lineSequence().firstOrNull()?.trim()?.trim('\r')
        return v?.takeIf { it.isNotBlank() }
    }

    private fun readKernelConfigConfigfsLines(): String? {
        val script = """
            if [ -r /proc/config.gz ]; then
              ( toybox gzip -dc /proc/config.gz 2>/dev/null \
                || toybox gunzip -c /proc/config.gz 2>/dev/null \
                || gunzip -c /proc/config.gz 2>/dev/null \
                || busybox zcat /proc/config.gz 2>/dev/null \
                || zcat /proc/config.gz 2>/dev/null ) \
                | grep -i configfs \
                | sed 's/^# //; s/ is not set/=NOT_SET/' || true
              exit 0
            fi

            CFG="/boot/config-`uname -r 2>/dev/null`"
            if [ -r "${'$'}CFG" ]; then
              cat "${'$'}CFG" 2>/dev/null \
                | grep -i configfs \
                | sed 's/^# //; s/ is not set/=NOT_SET/' || true
              exit 0
            fi

            echo "__NO_KERNEL_CONFIG__"
        """.trimIndent()

        val r = root.exec(script, timeoutSec = 15)
        val out = r.stdout.trim()
        if (out.isEmpty()) return null
        if (out.contains("__NO_KERNEL_CONFIG__")) return null
        return out
    }

    private fun readKernelConfigFlags(keys: List<String>): Map<String, String> {
        val uniqueKeys = LinkedHashSet(keys)
        val out = LinkedHashMap<String, String>()
        for (k in uniqueKeys) out[k] = "Unknown"
        val raw = readKernelConfigConfigfsLines() ?: return out

        val parsed = HashMap<String, String>(512)
        for (line in raw.lineSequence()) {
            val l = line.trim()
            if (l.isEmpty()) continue
            val idx = l.indexOf('=')
            if (idx <= 0) continue
            val name = l.substring(0, idx).trim()
            val value = l.substring(idx + 1).trim()
            if (name.startsWith("CONFIG_")) parsed[name] = value
        }

        for (k in uniqueKeys) {
            val v = parsed[k] ?: continue
            out[k] = when (v.lowercase(Locale.US)) {
                "y" -> "Yes"
                "m" -> "Module"
                "not_set" -> "Not set"
                "n" -> "No"
                else -> v
            }
        }
        return out
    }

    private fun collectKernelConfigInfo(): Map<String, Any?> {
        val keys = listOf(
            "CONFIG_CONFIGFS_FS",
            "CONFIG_IIO_CONFIGFS",
            "CONFIG_PCI_ENDPOINT_CONFIGFS",
            "CONFIG_USB_CONFIGFS",
            "CONFIG_USB_CONFIGFS_ACM",
            "CONFIG_USB_CONFIGFS_ECM",
            "CONFIG_USB_CONFIGFS_ECM_SUBSET",
            "CONFIG_USB_CONFIGFS_EEM",
            "CONFIG_USB_CONFIGFS_F_ACC",
            "CONFIG_USB_CONFIGFS_F_AUDIO_SRC",
            "CONFIG_USB_CONFIGFS_F_CCID",
            "CONFIG_USB_CONFIGFS_F_CDEV",
            "CONFIG_USB_CONFIGFS_F_DIAG",
            "CONFIG_USB_CONFIGFS_F_EMS",
            "CONFIG_USB_CONFIGFS_F_FS",
            "CONFIG_USB_CONFIGFS_F_GSI",
            "CONFIG_USB_CONFIGFS_F_HID",
            "CONFIG_USB_CONFIGFS_F_LB_SS",
            "CONFIG_USB_CONFIGFS_F_MIDI",
            "CONFIG_USB_CONFIGFS_F_PRINTER",
            "CONFIG_USB_CONFIGFS_F_QDSS",
            "CONFIG_USB_CONFIGFS_F_UAC1",
            "CONFIG_USB_CONFIGFS_F_UAC1_LEGACY",
            "CONFIG_USB_CONFIGFS_F_UAC2",
            "CONFIG_USB_CONFIGFS_F_UVC",
            "CONFIG_USB_CONFIGFS_MASS_STORAGE",
            "CONFIG_USB_CONFIGFS_NCM",
            "CONFIG_USB_CONFIGFS_OBEX",
            "CONFIG_USB_CONFIGFS_RNDIS",
            "CONFIG_USB_CONFIGFS_SERIAL",
            "CONFIG_USB_CONFIGFS_UEVENT",
        )

        val unameR = readKernelUnameR()
        val kver = if (!unameR.isNullOrBlank()) kernelVersionBase(unameR) else "Unknown"
        val flags = if (checkRoot()) readKernelConfigFlags(keys) else keys.associateWith { "Unknown" }

        val out = LinkedHashMap<String, Any?>()
        out["KERNEL_VERSION"] = kver
        for ((k, v) in flags) out[k] = v
        return out
    }

    fun getDiagnostics(): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        out["timestampMs"] = System.currentTimeMillis()
        out["status"] = getStatusSnapshot().toMap()

        try {
            out["kernelConfig"] = collectKernelConfigInfo()
        } catch (t: Throwable) {
            out["kernelConfigError"] = t.toString()
        }

        try {
            val raw = readKernelConfigConfigfsLines()
            out["kernelConfigRawFirstLines"] = raw?.lineSequence()?.take(60)?.toList() ?: emptyList<String>()
        } catch (t: Throwable) {
            out["kernelConfigRawError"] = t.toString()
        }

        try {
            out["rootId"] = root.exec("id").stdout.trim()
        } catch (t: Throwable) {
            out["rootIdError"] = t.toString()
        }

        try {
            out["sysUsbController"] = root.exec("getprop sys.usb.controller").stdout.trim()
        } catch (t: Throwable) {
            out["sysUsbControllerError"] = t.toString()
        }

        try {
            out["udcList"] = listUdcs()
        } catch (t: Throwable) {
            out["udcListError"] = t.toString()
        }

        try {
            val bases = listOf("/config/usb_gadget", "/sys/kernel/config/usb_gadget")
            val existing = ArrayList<String>()
            for (b in bases) {
                val ec = root.exec("test -d $b").exitCode
                if (ec == 0) existing.add(b)
            }
            out["configfsBases"] = existing
            out["configfsMount"] = root.exec("mount | grep -i configfs || true").stdout.trim()
        } catch (t: Throwable) {
            out["configfsError"] = t.toString()
        }

        try {
            out["paths"] = mapOf(
                "config" to root.exec("ls -ld /config 2>/dev/null || echo MISSING").stdout.trim(),
                "sysKernelConfig" to root.exec("ls -ld /sys/kernel/config 2>/dev/null || echo MISSING").stdout.trim(),
                "sysClassUdc" to root.exec("ls -ld /sys/class/udc 2>/dev/null || echo MISSING").stdout.trim(),
            )
        } catch (t: Throwable) {
            out["pathsError"] = t.toString()
        }

        try {
            val gadgets = root.exec("ls -1 /config/usb_gadget 2>/dev/null || true").stdout
                .split("\n")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            out["existingGadgetsInConfig"] = gadgets
        } catch (t: Throwable) {
            out["existingGadgetsError"] = t.toString()
        }

        return out
    }

    private fun emit(status: Status) {
        val map = status.toMap()
        main.post {
            try {
                sinkRef.get()?.success(map)
            } catch (_: Throwable) {
            }
        }
    }
}

package org.kaijinlab.gadgetfs

import java.util.Locale

object Configfs {
  data class ParsedProfile(
    val id: String,
    val name: String,
    val roleType: String,
    val manufacturer: String,
    val product: String,
    val serialNumber: String,
    val vendorId: Int,
    val productId: Int,
    val maxPowerMa: Int,
  )

  fun buildCreateAndBindScript(p: ParsedProfile, gadgetDir: String): String {
    val baseSelect = """
      set -e
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      if [ ! -d "${'$'}CFGBASE" ]; then
        echo "configfs usb_gadget not found" >&2
        exit 2
      fi

      cleanup_gadget() {
        _TARGET="${'$'}1"
        [ -d "${'$'}_TARGET" ] || return 0
        (echo "" > "${'$'}_TARGET/UDC") 2>/dev/null || true
        rm -f "${'$'}_TARGET"/configs/*/* 2>/dev/null || true
        for _d in "${'$'}_TARGET"/configs/*/strings/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/configs/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/functions/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/strings/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        rmdir "${'$'}_TARGET" 2>/dev/null || true
      }
    """.trimIndent()

    val mfg = shEscape(p.manufacturer)
    val prod = shEscape(p.product)
    val sn = shEscape(p.serialNumber)
    val gadget = sanitizeGadgetName(gadgetDir)

    val idVendor = String.format(Locale.US, "0x%04x", p.vendorId and 0xFFFF)
    val idProduct = String.format(Locale.US, "0x%04x", p.productId and 0xFFFF)

    val cfg = "c.1"

    val create = """
      $baseSelect

      # Choose UDC (before unbinding) so we can be less destructive
      UDC_NAME=${'$'}(getprop sys.usb.controller 2>/dev/null | tr -d '\r')
      if [ -z "${'$'}UDC_NAME" ]; then
        UDC_NAME=${'$'}(ls /sys/class/udc 2>/dev/null | head -n1 | tr -d '\r')
      fi
      if [ -z "${'$'}UDC_NAME" ]; then
        echo "No UDC found in /sys/class/udc" >&2
        exit 3
      fi

      # Clean up any previously created gadgetfs instances to release kernel HID minor numbers
      for _ex in "${'$'}CFGBASE"/gadgetfs*; do
        [ -d "${'$'}_ex" ] && cleanup_gadget "${'$'}_ex"
      done

      G="${'$'}CFGBASE/$gadget"
      mkdir -p "${'$'}G"
      cd "${'$'}G"

      echo $idVendor > idVendor
      echo $idProduct > idProduct
      echo 0x0200 > bcdUSB
      echo 0x0100 > bcdDevice

      mkdir -p strings/0x409
      echo $mfg > strings/0x409/manufacturer
      echo $prod > strings/0x409/product
      echo $sn > strings/0x409/serialnumber

      mkdir -p configs/$cfg/strings/0x409
      echo "Config 1" > configs/$cfg/strings/0x409/configuration
      echo ${p.maxPowerMa.coerceIn(2, 500)} > configs/$cfg/MaxPower
    """.trimIndent()

    val functions = when (p.roleType.lowercase(Locale.US)) {
      "mouse" -> buildMouseFunctionScript("hid.usb0")
      "keyboard" -> buildKeyboardFunctionScript("hid.usb0")
      else -> buildCompositeFunctionScript()
    }

    val link = """
      # Link functions into config
      for f in ${'$'}(ls -1 functions 2>/dev/null); do
        if [ ! -e "configs/$cfg/${'$'}f" ]; then
          ln -s "functions/${'$'}f" "configs/$cfg/${'$'}f"
        fi
      done
    """.trimIndent()

    val bind = """
      # Unbind other gadgets bound to the same UDC (best-effort), but do not nuke everything
      for U in "${'$'}CFGBASE"/*/UDC; do
        [ -f "${'$'}U" ] || continue
        # Skip our gadget's UDC file
        if [ "${'$'}U" = "${'$'}G/UDC" ]; then
          continue
        fi
        CUR=${'$'}(cat "${'$'}U" 2>/dev/null | tr -d '\r')
        if [ "${'$'}CUR" = "${'$'}UDC_NAME" ]; then
          (echo "" > "${'$'}U") 2>/dev/null || true
        fi
      done

      echo "${'$'}UDC_NAME" > UDC
      echo "Bound to UDC: ${'$'}UDC_NAME"

      # Ensure character devices exist in /dev and have proper permissions
      for fn in functions/hid.*; do
        [ -d "${'$'}fn" ] || continue
        if [ -f "${'$'}fn/dev" ]; then
          DEV_PAIR=${'$'}(cat "${'$'}fn/dev" 2>/dev/null | tr -d '\r')
          MAJOR=${'$'}{DEV_PAIR%:*}
          MINOR=${'$'}{DEV_PAIR#*:}
          NODE="/dev/hidg${'$'}MINOR"
          if [ ! -c "${'$'}NODE" ] && [ -n "${'$'}MAJOR" ] && [ -n "${'$'}MINOR" ]; then
            rm -f "${'$'}NODE" 2>/dev/null || true
            mknod "${'$'}NODE" c "${'$'}MAJOR" "${'$'}MINOR" 2>/dev/null || true
          fi
          chmod 666 "${'$'}NODE" 2>/dev/null || true
        fi
      done
      chmod 666 /dev/hidg* 2>/dev/null || true
    """.trimIndent()

    return listOf(create, functions, link, bind).joinToString("\n\n") + "\n"
  }

  fun buildUnbindAndCleanupScript(gadgetDir: String): String {
    val gadget = sanitizeGadgetName(gadgetDir)
    return """
      set -e
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      cleanup_gadget() {
        _TARGET="${'$'}1"
        [ -d "${'$'}_TARGET" ] || return 0
        (echo "" > "${'$'}_TARGET/UDC") 2>/dev/null || true
        rm -f "${'$'}_TARGET"/configs/*/* 2>/dev/null || true
        for _d in "${'$'}_TARGET"/configs/*/strings/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/configs/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/functions/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/strings/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        rmdir "${'$'}_TARGET" 2>/dev/null || true
      }
      G="${'$'}CFGBASE/$gadget"
      cleanup_gadget "${'$'}G"
    """.trimIndent() + "\n"
  }

  fun buildPanicStopScript(): String {
    return """
      set -e
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      cleanup_gadget() {
        _TARGET="${'$'}1"
        [ -d "${'$'}_TARGET" ] || return 0
        (echo "" > "${'$'}_TARGET/UDC") 2>/dev/null || true
        rm -f "${'$'}_TARGET"/configs/*/* 2>/dev/null || true
        for _d in "${'$'}_TARGET"/configs/*/strings/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/configs/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/functions/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        for _d in "${'$'}_TARGET"/strings/*; do [ -d "${'$'}_d" ] && rmdir "${'$'}_d" 2>/dev/null || true; done
        rmdir "${'$'}_TARGET" 2>/dev/null || true
      }
      if [ -d "${'$'}CFGBASE" ]; then
        find "${'$'}CFGBASE" -maxdepth 2 -name UDC -type f -exec sh -c 'echo "" > "${'$'}1" 2>/dev/null || true' _ {} \;
        for _ex in "${'$'}CFGBASE"/gadgetfs*; do
          [ -d "${'$'}_ex" ] && cleanup_gadget "${'$'}_ex"
        done
      fi
    """.trimIndent() + "\n"
  }

  private fun buildMouseFunctionScript(fn: String): String {
    val desc = bytesToHexString(HidSpec.MOUSE_REPORT_DESC)
    return """
      mkdir -p functions/$fn
      echo 2 > functions/$fn/protocol
      echo 1 > functions/$fn/subclass
      echo 4 > functions/$fn/report_length
      echo '$desc' | toybox xxd -r -p > functions/$fn/report_desc
    """.trimIndent()
  }

  private fun buildKeyboardFunctionScript(fn: String): String {
    val desc = bytesToHexString(HidSpec.KEYBOARD_REPORT_DESC)
    return """
      mkdir -p functions/$fn
      echo 1 > functions/$fn/protocol
      echo 1 > functions/$fn/subclass
      echo 8 > functions/$fn/report_length
      echo '$desc' | toybox xxd -r -p > functions/$fn/report_desc
    """.trimIndent()
  }

  private fun buildCompositeFunctionScript(): String {
    return listOf(
      buildKeyboardFunctionScript("hid.usb0"),
      buildMouseFunctionScript("hid.usb1")
    ).joinToString("\n\n")
  }

  private fun bytesToHexString(bytes: ByteArray): String {
    val sb = StringBuilder(bytes.size * 2)
    for (b in bytes) {
      sb.append(String.format(Locale.US, "%02x", b.toInt() and 0xFF))
    }
    return sb.toString()
  }

  private fun shEscape(s: String): String {
    return "'" + s.replace("'", "'\"'\"'") + "'"
  }

  private fun sanitizeGadgetName(name: String): String {
    val cleaned = name.trim().ifEmpty { "gadgetfs" }
    return cleaned.replace(Regex("[^a-zA-Z0-9._-]"), "_")
  }
}

package org.kaijinlab.gadgetfs

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    private lateinit var logBus: LogBus
    private lateinit var manager: GadgetManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Keep a single backend instance per process.
        val backend = BackendHolder.get(applicationContext)
        logBus = backend.logBus
        manager = backend.manager

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Methods
        MethodChannel(messenger, CHANNEL_METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRoot" -> runAsync(result) { manager.checkRoot() }
                "checkSupport" -> runAsync(result) { manager.checkSupport() }
                "listUdcs" -> runAsync(result) { manager.listUdcs() }
                "getStatus" -> runAsync(result) { manager.getStatusSnapshot().toMap() }
                "getDiagnostics" -> runAsync(result) { manager.getDiagnostics() }
                "activateProfile" -> {
                    val map = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    runAsync(result) {
                        manager.activate(map)
	                    null
                    }
                }
	            "deactivate" -> runAsync(result) {
	                manager.deactivate(); null
	            }
	            "panicStop" -> runAsync(result) {
	                manager.panicStop(); null
	            }
                "testMouseMove" -> {
                    val args = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any>()
                    val dx = (args["dx"] as? Number)?.toInt() ?: 8
                    val dy = (args["dy"] as? Number)?.toInt() ?: 0
                    val wheel = (args["wheel"] as? Number)?.toInt() ?: 0
                    val buttons = (args["buttons"] as? Number)?.toInt() ?: 0
                    runAsync(result) {
                        manager.testMouseMove(dx, dy, wheel, buttons)
	                    null
                    }
                }
                "testKeyboardKey" -> {
                    val args = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any>()
	                // Dart sends: {'label': '<key>'}
	                val key = args["label"]?.toString() ?: args["key"]?.toString() ?: "A"
                    runAsync(result) {
                        manager.testKeyboardKey(key)
	                    null
                    }
                }
	            "testCtrlAltDel" -> runAsync(result) {
	                manager.testCtrlAltDel(); null
	            }
                else -> result.notImplemented()
            }
        }

        // Logs stream
        EventChannel(messenger, CHANNEL_LOGS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                logBus.attach(events)
            }

            override fun onCancel(arguments: Any?) {
                logBus.detach()
            }
        })

        // Status stream
        EventChannel(messenger, CHANNEL_STATUS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                manager.attachStatusSink(events)
            }

            override fun onCancel(arguments: Any?) {
                manager.detachStatusSink()
            }
        })
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (t: Throwable) {
                mainHandler.post { result.error("ERR", t.message, null) }
            }
        }
    }

    companion object {
        private const val CHANNEL_METHODS = "org.kaijinlab.gadgetfs/gadget"
        private const val CHANNEL_LOGS = "org.kaijinlab.gadgetfs/gadget_logs"
        private const val CHANNEL_STATUS = "org.kaijinlab.gadgetfs/gadget_status"
    }
}

private object BackendHolder {
    @Volatile
    private var instance: Backend? = null

    fun get(ctx: android.content.Context): Backend {
        return instance ?: synchronized(this) {
            instance ?: Backend(ctx.applicationContext).also { instance = it }
        }
    }

    class Backend(ctx: android.content.Context) {
        val logBus = LogBus()
        val manager = GadgetManager(ctx, logBus)
    }
}

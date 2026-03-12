package `in`.drdna.ledfx

import io.flutter.plugin.common.EventChannel

object RecordingBridge {
    private val eventSinks = mutableMapOf<Boolean, EventChannel.EventSink>()

    fun setup(
            eventChannel: EventChannel,
            isBackground: Boolean = false
    ) {

        eventChannel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                        if (events != null) {
                            eventSinks[isBackground] = events
                        }
                    }
                    override fun onCancel(args: Any?) {
                        eventSinks.remove(isBackground)
                    }
                }
        )
    }

    fun removeUiSink() {
        eventSinks.remove(false)
    }

    // ===== Helpers to send events back to Flutter =====

    fun sendAudio(doubles: List<Double>) {
        eventSinks.values.forEach { it.success(mapOf("type" to "audio", "data" to doubles)) }
    }

    fun sendState(state: String) {
        // state = "started", "paused", "resumed", "stopped"
        eventSinks.values.forEach { it.success(mapOf("type" to "state", "value" to state)) }
    }

    fun sendError(message: String) {
        eventSinks.values.forEach { it.success(mapOf("type" to "error", "message" to message)) }
    }
}

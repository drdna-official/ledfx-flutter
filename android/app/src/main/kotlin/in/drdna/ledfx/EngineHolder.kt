package `in`.drdna.ledfx

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.view.FlutterCallbackInformation

object EngineHolder {
    var flutterEngine: FlutterEngine? = null

    fun ensureEngineStarted(context: Context, handle: Long) {
        if (flutterEngine != null) return

        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) loader.startInitialization(context)

        loader.ensureInitializationCompleteAsync(context, null, Handler(Looper.getMainLooper())) {
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(handle)
            if (callbackInfo != null && flutterEngine == null) {
                flutterEngine = FlutterEngine(context)

                val eventChannel =
                        EventChannel(
                                flutterEngine!!.dartExecutor.binaryMessenger,
                                "system_audio_recorder/events"
                        )
                RecordingBridge.setup(eventChannel, isBackground = true)

                val dartCallback =
                        DartExecutor.DartCallback(
                                context.assets,
                                loader.findAppBundlePath(),
                                callbackInfo
                        )
                flutterEngine!!.dartExecutor.executeDartCallback(dartCallback)
            }
        }
    }
}

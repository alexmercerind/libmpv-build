package io.mpv.mpv_libs;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

public class MpvLibsPlugin implements FlutterPlugin {
    static {
        try {
            System.loadLibrary("mpv");
        } catch (Throwable e) {
        }
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding flutterPluginBinding) {
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
    }
}

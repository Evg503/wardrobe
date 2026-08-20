package com.example.wardrobe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Регистрируем ARCore PlatformView factory.
        // Передаём this (Activity) явно — Flutter передаёт PlatformView
        // ContextWrapper, который не является Activity напрямую.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "wardrobe/arcore_view",
            ArCorePlugin(flutterEngine.dartExecutor.binaryMessenger, this)
        )
    }
}

package com.example.wardrobe

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Фабрика PlatformView для встраивания ARCore-вида во Flutter.
 *
 * Принимает [activity] явно — Flutter PlatformView передаёт ContextWrapper,
 * а не Activity, поэтому прямой каст context as Activity всегда падает.
 *
 * Регистрируется в MainActivity как "wardrobe/arcore_view".
 */
class ArCorePlugin(
    private val messenger: BinaryMessenger,
    private val activity: Activity,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArCoreView(context, messenger, viewId, activity)
    }
}

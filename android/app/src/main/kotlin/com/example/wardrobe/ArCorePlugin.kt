package com.example.wardrobe

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Фабрика PlatformView для встраивания ARCore-вида во Flutter.
 *
 * Регистрируется в MainActivity как "wardrobe/arcore_view".
 */
class ArCorePlugin(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArCoreView(context, messenger, viewId)
    }
}

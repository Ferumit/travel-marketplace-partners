package com.explora.partners

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import com.yandex.mapkit.MapKitFactory

class MainActivity: FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    MapKitFactory.setApiKey("YOUR_YANDEX_MAPKIT_API_KEY") 
    super.configureFlutterEngine(flutterEngine)
  }
}

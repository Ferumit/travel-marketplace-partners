package com.explora.partners

import android.app.Application
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MapKitFactory.setApiKey("YOUR_YANDEX_MAPKIT_API_KEY")
    }
}

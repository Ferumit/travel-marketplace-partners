/// Centralised configuration constants for Explora Partners.
///
/// All API keys, IDs and tuneable thresholds live here so they can be
/// updated in one place without hunting through the source tree.
abstract final class AppConfig {
  // ── Bridgefy BLE-MESH ──────────────────────────────────────────────────────
  /// Bridgefy SDK API key.  Replace with production key before release.
  static const String bridgefyApiKey = 'YOUR_BRIDGEFY_API_KEY';

  /// Logical room/channel used by all Explora Partners devices.
  static const String meshRoomId = 'explora-mesh';

  /// Approximate BLE mesh radius (km) shown in the UI.
  static const double meshRadiusKm = 2.4;

  // ── Location broadcast throttle ────────────────────────────────────────────
  /// Minimum distance (metres) moved before broadcasting GPS to Firestore.
  static const double broadcastDistanceM = 10.0;

  /// Minimum time (seconds) between GPS broadcasts.
  static const int broadcastIntervalSec = 15;

  // ── Map camera throttle ────────────────────────────────────────────────────
  static const Duration uiThrottle = Duration(milliseconds: 700);
  static const Duration cameraThrottle = Duration(milliseconds: 1100);
}

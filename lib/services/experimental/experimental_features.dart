import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/global_config.dart' show GlobalState;

class ExperimentalFeatures {
  static const _tunnelProxyKey = 'tunnelProxyEnabled';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_tunnelProxyKey);
    if (enabled == null) {
      GlobalState.setConnectionMode(GlobalState.connectionMode.value);
    } else {
      GlobalState.setTunnelModeEnabled(enabled);
    }
    GlobalState.tunnelProxyEnabled.addListener(() {
      prefs.setBool(_tunnelProxyKey, GlobalState.tunnelProxyEnabled.value);
    });
  }
}

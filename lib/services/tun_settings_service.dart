import 'package:shared_preferences/shared_preferences.dart';

import '../utils/global_config.dart' show GlobalState;

class TunSettingsService {
  static const _prefsKey = 'tunSettingsEnabled';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    GlobalState.tunSettingsEnabled.value = enabled;
    GlobalState.tunSettingsEnabled.addListener(() {
      prefs.setBool(_prefsKey, GlobalState.tunSettingsEnabled.value);
    });
  }
}

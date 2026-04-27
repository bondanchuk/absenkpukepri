import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String keyNip = "nip";
  static const String keyName = "name";

  // Simpan session
  static Future<void> saveSession({
    required String nip,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNip, nip);
    await prefs.setString(keyName, name);
  }

  // Ambil session
  static Future<Map<String, String>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final nip = prefs.getString(keyNip);
    final name = prefs.getString(keyName);

    if (nip == null || name == null) return null;

    return {
      "nip": nip,
      "name": name,
    };
  }

  // Hapus session (logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyNip);
    await prefs.remove(keyName);
  }
}

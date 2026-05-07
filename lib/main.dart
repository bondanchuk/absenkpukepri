import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Inisialisasi format tanggal Indonesia
  await initializeDateFormatting('id_ID', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // ✅ Fungsi untuk menentukan halaman awal (Login atau Home)
  Future<Widget> _getStartPage() async {
    final prefs = await SharedPreferences.getInstance();
    final nip = prefs.getString("nip");
    final name = prefs.getString("name");

    // Jika data NIP dan Nama ada di memori HP, langsung ke Home
    if (nip != null && name != null) {
      return HomePage(nip: nip, name: name);
    }

    // Jika tidak ada, arahkan ke Login
    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "ABSENSI KPU KEPRI", // ✅ Perbaikan Typo
      theme: ThemeData(
        primaryColor: const Color(0xFF7A0C10),
        fontFamily: "Poppins",
      ),
      home: FutureBuilder<Widget>(
        future: _getStartPage(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF7A0C10)),
              ),
            );
          }
          return snapshot.data ?? const LoginPage();
        },
      ),
    );
  }
}

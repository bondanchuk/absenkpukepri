import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ Untuk Simpan Sesi
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nipController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final nip = nipController.text.trim();
      final pass = passwordController.text.trim();

      // 1) Login Anonymous untuk mendapatkan UID Perangkat
      final userCred = await FirebaseAuth.instance.signInAnonymously();
      final authUid = userCred.user!.uid;

      // 2) Ambil data user dari Firestore
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(nip)
          .get();
      if (!doc.exists) throw Exception("NIP tidak terdaftar");

      final data = doc.data()!;
      if (data["isActive"] != true) throw Exception("Akun Anda dinonaktifkan");
      if (data["password"] != pass) throw Exception("Password salah");

      // ✅ 3) LOGIKA KUNCI 1 AKUN 1 DEVICE (Device Binding)
      final savedUid = data["uid"];

      // CEK A: Apakah HP ini sudah terikat dengan NIP lain?
      final otherUser = await FirebaseFirestore.instance
          .collection("users")
          .where("uid", isEqualTo: authUid)
          .get();

      if (otherUser.docs.isNotEmpty && otherUser.docs.first.id != nip) {
        throw Exception("HP ini sudah terdaftar untuk akun lain.");
      }

      // CEK B: Apakah NIP ini mencoba login di HP yang berbeda?
      if (savedUid != null && savedUid.toString().isNotEmpty) {
        if (savedUid != authUid) {
          throw Exception("Akun Anda sudah terkunci di HP lain.");
        }
      } else {
        // Jika akun belum punya ikatan UID, ikat ke HP ini sekarang
        await FirebaseFirestore.instance.collection("users").doc(nip).set({
          "uid": authUid,
        }, SetOptions(merge: true));
      }

      // ✅ 4) SIMPAN SESI KE MEMORI LOKAL (Agar tidak perlu login lagi)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("nip", nip);
      await prefs.setString("name", data["name"] ?? "");

      if (!mounted) return;

      // Pindah ke Home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(nip: nip, name: data["name"] ?? ""),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ $e"), backgroundColor: Colors.red),
      );
      await FirebaseAuth.instance.signOut();
    } finally {
      setState(() => _loading = false);
    }
  }

  // ... (Sisa kode UI build tetap sama seperti revisi sebelumnya)
  @override
  Widget build(BuildContext context) {
    // Gunakan UI yang sudah kita rapikan sebelumnya dengan icon dan teks putih
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Image.asset("assets/logo.png", height: 120),
                  const SizedBox(height: 20),
                  const Text(
                    "ABSENSI KPU KEPRI",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF7A0C10),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: nipController,
                          decoration: InputDecoration(
                            hintText: "NIP",
                            prefixIcon: const Icon(
                              Icons.badge,
                              color: Color(0xFF7A0C10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: "Password",
                            prefixIcon: const Icon(
                              Icons.lock,
                              color: Color(0xFF7A0C10),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _loading ? null : login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7A0C10),
                            ),
                            child: _loading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

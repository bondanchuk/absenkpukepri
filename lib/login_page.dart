import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _obscurePassword = true; // ✅ Untuk fitur hide/show password

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final nip = nipController.text.trim();
      final pass = passwordController.text.trim();

      // ✅ 1) LOGIN ANONYMOUS DULU
      final userCred = await FirebaseAuth.instance.signInAnonymously();
      final authUid = userCred.user!.uid;

      // ✅ 2) BARU BACA USER DOCUMENT
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(nip)
          .get();

      if (!doc.exists) throw Exception("NIP tidak terdaftar");

      final data = doc.data()!;

      // ✅ 3) cek aktif
      if (data["isActive"] != true) throw Exception("Akun nonaktif");

      // ✅ 4) cek password
      if (data["password"] != pass) throw Exception("Password salah");

      // ✅ 5) cek uid dalam Firestore
      final savedUid = data["uid"];

      if (savedUid != null && savedUid.toString().isNotEmpty) {
        // kalau uid sudah ada, harus sama
        if (savedUid != authUid) {
          throw Exception("Session tidak valid. Silakan login ulang.");
        }
      } else {
        // kalau uid masih kosong, isi uid = authUid
        await FirebaseFirestore.instance.collection("users").doc(nip).set({
          "uid": authUid,
        }, SetOptions(merge: true));
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(nip: nip, name: data["name"] ?? ""),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ $e")));

      // optional: logout auth kalau gagal login
      await FirebaseAuth.instance.signOut();
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    nipController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA), // Background senada dengan Home
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ LOGO KPU
                  Image.asset(
                    "assets/logo.png",
                    height: 120,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.account_balance,
                        size: 100,
                        color: Color(0xFF7A0C10),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // ✅ JUDUL (Typo Spasi Diperbaiki)
                  const Text(
                    "ABSENSI KPU KEPRI",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF7A0C10),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // ✅ CARD FORM LOGIN (Lebih Premium)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // ✅ Kolom Input NIP
                        TextFormField(
                          controller: nipController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: "Nomor Induk Pegawai (NIP)",
                            hintStyle: const TextStyle(
                              color: Colors.black45,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.badge,
                              color: Color(0xFF7A0C10),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFD),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0xFF7A0C10),
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? "NIP wajib diisi"
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // ✅ Kolom Input Password
                        TextFormField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              login(), // Login via tombol Enter/Done di keyboard
                          decoration: InputDecoration(
                            hintText: "Password",
                            hintStyle: const TextStyle(
                              color: Colors.black45,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.lock,
                              color: Color(0xFF7A0C10),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFD),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0xFF7A0C10),
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? "Password wajib diisi"
                              : null,
                        ),
                        const SizedBox(height: 30),

                        // ✅ Tombol Login
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _loading ? null : login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7A0C10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    "Login",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors
                                          .white, // ✅ Teks putih agar terlihat jelas
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ✅ Footer
                  const Text(
                    "KPU Provinsi Kepulauan Riau\nTim IT © 2026",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black38,
                      fontSize: 12,
                      height: 1.5,
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

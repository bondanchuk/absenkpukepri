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
      final doc =
          await FirebaseFirestore.instance.collection("users").doc(nip).get();

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
          builder: (_) => HomePage(
            nip: nip,
            name: data["name"] ?? "",
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ $e")),
      );

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
      backgroundColor: const Color(0xFFF4F6FA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset("assets/logo.png", height: 110),
                const SizedBox(height: 20),
                const Text(
                  "ABSENSI KP UKEPRI",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7A0C10),
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: nipController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: "Nomor Induk Pegawai (NIP)",
                          filled: true,
                          fillColor: const Color(0xFFF4F6FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? "NIP wajib diisi"
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: "Password",
                          filled: true,
                          fillColor: const Color(0xFFF4F6FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? "Password wajib diisi"
                                : null,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7A0C10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 16,
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ReportPage extends StatefulWidget {
  final String nip;
  final String docId;

  const ReportPage({super.key, required this.nip, required this.docId});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  bool _hasCheckedOut = false; // Status apakah sudah absen pulang

  final TextEditingController tasksController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadExistingReport();
  }

  // ✅ Fungsi Cek Batas Waktu Akhir (23.59)
  bool isExpired() {
    final now = DateTime.now();
    final deadline = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return now.isAfter(deadline);
  }

  // ✅ Fungsi Cek Belum Waktunya (Boleh jika sudah pulang ATAU sudah jam 17.00)
  bool isTooEarly() {
    if (_hasCheckedOut) return false; // Sudah pulang = Bebas isi
    final now = DateTime.now();
    return now.hour < 17; // Jika belum pulang, harus lewat jam 17.00
  }

  Future<void> loadExistingReport() async {
    final docRef = FirebaseFirestore.instance
        .collection("attendance")
        .doc(widget.docId);
    final snapshot = await docRef.get();

    if (snapshot.exists) {
      final data = snapshot.data()!;
      if (data['checkOutTime'] != null) {
        setState(() => _hasCheckedOut = true);
      }
      if (data['performanceReport'] != null) {
        final report = data['performanceReport'] as Map<String, dynamic>;
        setState(() {
          tasksController.text = report['tasks'] ?? "";
          notesController.text = report['notes'] ?? "";
        });
      }
    }
  }

  Future<void> submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    if (isTooEarly()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "⏳ Anda belum absen pulang atau belum melewati jam 17.00 WIB",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (isExpired()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Batas waktu pengisian laporan telah berakhir"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(widget.docId);
      final now = DateTime.now();

      await docRef.set({
        "nip": widget.nip,
        "date": DateFormat("yyyy-MM-dd").format(now),
        "reportSubmitted":
            true, // ✅ KEMBALI DITAMBAHKAN SESUAI VERSI SEBELUMNYA
        "performanceReport": {
          "tasks": tasksController.text.trim(),
          "notes": notesController.text.trim(),
          "submittedAt": now.toIso8601String(),
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Laporan berhasil dikirim!")),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Gagal mengirim laporan: $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool expiredStatus = isExpired();
    final bool earlyStatus = isTooEarly();
    final bool cannotSubmit = expiredStatus || earlyStatus;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          "Laporan Kinerja",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0xFF7A0C10),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFbeaea),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.task_alt,
                                  color: Color(0xFF7A0C10),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  "Detail Kinerja",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF7A0C10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          if (earlyStatus)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "Laporan hanya dapat diisi setelah Anda Absen Pulang ATAU setelah pukul 17.00 WIB.",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const Text(
                            "Apa yang Anda kerjakan hari ini?",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: tasksController,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText:
                                  "Contoh:\n1. Menyusun dokumen sosialisasi\n2. Rapat koordinasi internal",
                              hintStyle: const TextStyle(
                                color: Colors.black38,
                                fontSize: 13,
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
                                ? 'Mohon isi detail pekerjaan'
                                : null,
                          ),
                          const SizedBox(height: 20),

                          const Text(
                            "Catatan Tambahan / Kendala (Opsional)",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: notesController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: "Tuliskan kendala jika ada...",
                              hintStyle: const TextStyle(
                                color: Colors.black38,
                                fontSize: 13,
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
                          ),
                          const SizedBox(height: 30),

                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cannotSubmit
                                    ? Colors.grey
                                    : const Color(0xFF7A0C10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 2,
                              ),
                              onPressed: (_loading || cannotSubmit)
                                  ? null
                                  : submitReport,
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      expiredStatus
                                          ? "Waktu Berakhir"
                                          : "✅ Kirim Laporan",
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

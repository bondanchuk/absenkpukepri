import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ReportPage extends StatefulWidget {
  final String nip;
  final String docId;

  const ReportPage({
    super.key,
    required this.nip,
    required this.docId,
  });

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  final TextEditingController tasksController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadExistingReport();
  }

  /// ✅ load report jika sudah pernah isi
  Future<void> loadExistingReport() async {
    final docRef =
        FirebaseFirestore.instance.collection("attendance").doc(widget.docId);
    final snapshot = await docRef.get();

    if (snapshot.exists) {
      final data = snapshot.data()!;
      if (data["performanceReport"] != null) {
        final report = data["performanceReport"];
        tasksController.text = report["tasks"] ?? "";
        notesController.text = report["notes"] ?? "";
      }
    }
  }

  Future<void> submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final docRef =
          FirebaseFirestore.instance.collection("attendance").doc(widget.docId);

      await docRef.set({
        "performanceReport": {
          "tasks": tasksController.text.trim(),
          "notes": notesController.text.trim(),
          "createdAt": FieldValue.serverTimestamp(),
        },
        "reportSubmitted": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Laporan berhasil dikirim")),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    tasksController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Widget _header(String dateLabel) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 55, 20, 20),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF7A0C10),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Laporan Kinerja",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF7A0C10), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat("EEEE, dd MMMM yyyy", "id_ID").format(DateTime.now());

    final attendanceRef =
        FirebaseFirestore.instance.collection("attendance").doc(widget.docId);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Column(
        children: [
          _header(dateLabel),

          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: attendanceRef.snapshots(),
              builder: (context, snapshot) {
                bool sudahCheckout = false;
                bool sudahReport = false;

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  sudahCheckout = data["checkOutTime"] != null;
                  sudahReport = data["reportSubmitted"] == true;
                }

                // ✅ Jika belum checkout, tampilkan warning card
                if (!sudahCheckout) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: _card(
                      child: Column(
                        children: const [
                          Icon(Icons.info_outline,
                              size: 48, color: Colors.orange),
                          SizedBox(height: 12),
                          Text(
                            "Laporan hanya bisa diisi setelah absen pulang.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Silakan lakukan absen pulang terlebih dahulu.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (sudahReport)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Laporan hari ini sudah dikirim ✅",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      _card(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Isi Laporan Harian",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),

                              TextFormField(
                                controller: tasksController,
                                maxLines: 5,
                                decoration: _inputDecoration(
                                  "Pekerjaan hari ini (wajib)",
                                  "Contoh: Membuat UI dashboard, update absensi, perbaiki bug...",
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Pekerjaan wajib diisi";
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              TextFormField(
                                controller: notesController,
                                maxLines: 4,
                                decoration: _inputDecoration(
                                  "Catatan tambahan (opsional)",
                                  "Contoh: Kendala hari ini / progress / kebutuhan support...",
                                ),
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7A0C10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed: _loading ? null : submitReport,
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
                                          "✅ Kirim Laporan",
                                          style: TextStyle(
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

                      const SizedBox(height: 30),
                      const Text(
                        "Tim IT Diskominfo Kabupaten Bintan 2025",
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

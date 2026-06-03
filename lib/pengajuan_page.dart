import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import 'cloudinary_service.dart';

class PengajuanPage extends StatefulWidget {
  final String nip;
  final String name;

  const PengajuanPage({super.key, required this.nip, required this.name});

  @override
  State<PengajuanPage> createState() => _PengajuanPageState();
}

class _PengajuanPageState extends State<PengajuanPage> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  String? _selectedType;
  final TextEditingController _reasonController = TextEditingController();
  File? _attachmentPreview;

  final List<String> _kategori = ["Izin", "Sakit", "Perjalanan Dinas"];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Bisa pilih dari galeri atau kamera untuk surat tugas/surat sakit
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() {
        _attachmentPreview = File(picked.path);
      });
    }
  }

  Future<void> _submitPengajuan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Pilih kategori permohonan terlebih dahulu."),
        ),
      );
      return;
    }

    // Validasi: Perjalanan Dinas WAJIB upload dokumen
    if (_selectedType == "Perjalanan Dinas" && _attachmentPreview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "❌ Perjalanan Dinas wajib melampirkan foto Surat Tugas.",
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final now = DateTime.now();
      final docId = "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
      final docRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(docId);

      final existingDoc = await docRef.get();
      if (existingDoc.exists && existingDoc.data()?['checkInTime'] != null) {
        throw Exception(
          "Anda sudah absen masuk hari ini. Tidak bisa mengajukan $_selectedType.",
        );
      }

      String? attachmentUrl;
      if (_attachmentPreview != null) {
        final compressedFile = await CloudinaryService.compressTo200KB(
          _attachmentPreview!,
        );
        if (compressedFile != null) {
          attachmentUrl = await CloudinaryService.uploadImage(compressedFile);
        }
      }

      // Simpan ke Firestore
      await docRef.set({
        "nip": widget.nip,
        "date": DateFormat("yyyy-MM-dd").format(now),
        "status": _selectedType, // Penanda khusus Izin/Sakit/Dinas
        "reason": _reasonController.text.trim(),
        "attachmentUrl": attachmentUrl,
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Permohonan $_selectedType berhasil dikirim!"),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          "Permohonan Absensi",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Kategori Permohonan",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: const Text(
                            "Pilih Kategori",
                            style: TextStyle(
                              color: Colors.black45,
                              fontSize: 14,
                            ),
                          ),
                          value: _selectedType,
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Color(0xFF7A0C10),
                          ),
                          items: _kategori
                              .map(
                                (kat) => DropdownMenuItem(
                                  value: kat,
                                  child: Text(
                                    kat,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() => _selectedType = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      "Keterangan / Alasan",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Tuliskan keterangan detail...",
                        filled: true,
                        fillColor: const Color(0xFFF8FAFD),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF7A0C10),
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Keterangan wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        const Text(
                          "Bukti Lampiran",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_selectedType == "Perjalanan Dinas")
                          const Text(
                            " (Wajib)",
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          const Text(
                            " (Opsional)",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickImage,
                      child: Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: _attachmentPreview != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _attachmentPreview!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    color: Colors.grey,
                                    size: 30,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Ambil Foto Dokumen / Surat",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7A0C10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _loading ? null : _submitPengajuan,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Kirim Permohonan",
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
    );
  }
}

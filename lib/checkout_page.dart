import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import 'location_service.dart';
import 'cloudinary_service.dart';

class CheckOutPage extends StatefulWidget {
  final String nip;
  const CheckOutPage({super.key, required this.nip});

  @override
  State<CheckOutPage> createState() => _CheckOutPageState();
}

class _CheckOutPageState extends State<CheckOutPage> {
  bool _loading = false;

  // ✅ Koordinat kantor
  final double officeLat = 0.8969112;
  final double officeLng = 104.4773251;
  final double radiusMeters = 300;

  String debugInfo = "";
  File? selfiePreview;

  // ✅ Fungsi Cek Belum Waktunya (Sebelum 15.00)
  bool isTooEarly() {
    final now = DateTime.now();
    final startTime = DateTime(
      now.year,
      now.month,
      now.day,
      15,
      0,
    ); // Jam 15:00
    return now.isBefore(startTime);
  }

  // ✅ Fungsi Cek Batas Waktu (23.59)
  bool isExpired() {
    final now = DateTime.now();
    // Batas adalah jam 23:59:59 pada hari yang sama
    final deadline = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return now.isAfter(deadline);
  }

  String todayDocId() {
    final now = DateTime.now();
    return "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
  }

  Future<void> checkOut() async {
    // ✅ Validasi Waktu Mulai Absen Pulang
    if (isTooEarly()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "⏳ Belum waktunya pulang. Absen pulang dimulai jam 15.00 WIB.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // ✅ Validasi Batas Akhir Waktu
    if (isExpired()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Batas waktu absen pulang hari ini telah berakhir."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // ✅ 0) Cek doc attendance hari ini
      final docId = todayDocId();
      final docRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(docId);

      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        throw Exception("Kamu belum absen masuk hari ini ❌");
      }

      final data = snapshot.data()!;
      if (data["checkInTime"] == null) {
        throw Exception("Kamu belum absen masuk hari ini ❌");
      }

      if (data["checkOutTime"] != null) {
        throw Exception("Kamu sudah absen pulang hari ini ✅");
      }

      // ✅ 1) Ambil lokasi
      final pos = await LocationService.getCurrentPosition();

      // Hitung jarak ke kantor
      final dist = LocationService.distanceInMeters(
        pos.latitude,
        pos.longitude,
        officeLat,
        officeLng,
      );

      setState(() {
        debugInfo =
            "Lat: ${pos.latitude}\n"
            "Lng: ${pos.longitude}\n"
            "Accuracy: ${pos.accuracy.toStringAsFixed(1)} m\n"
            "Distance: ${dist.toStringAsFixed(1)} m\n"
            "Mocked: ${pos.isMocked}";
      });

      // ✅ 2) Validasi akurasi GPS
      if (pos.accuracy > 25) {
        throw Exception(
          "Akurasi GPS terlalu buruk (${pos.accuracy.toStringAsFixed(1)}m).\n"
          "Coba lagi di tempat terbuka.",
        );
      }

      // ✅ 3) Deteksi mock location
      if (pos.isMocked) {
        throw Exception(
          "Mock Location terdeteksi.\n"
          "Matikan Fake GPS / Mock Location.",
        );
      }

      // ✅ 4) Cek jarak ke kantor
      if (dist > radiusMeters) {
        throw Exception(
          "Di luar area kantor.\n"
          "Jarak: ${dist.toStringAsFixed(1)} m",
        );
      }

      // ✅ 5) Ambil selfie pulang
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100,
      );

      if (picked == null) {
        throw Exception("Selfie wajib untuk absen pulang.");
      }

      final original = File(picked.path);
      setState(() => selfiePreview = original);

      // ✅ 6) Compress foto sampai <= 200KB
      final compressed = await CloudinaryService.compressTo200KB(original);

      if (compressed == null) {
        throw Exception("Gagal compress foto.");
      }

      final compressedSize = await compressed.length();
      if (compressedSize > 200 * 1024) {
        throw Exception(
          "Foto masih terlalu besar (${(compressedSize / 1024).toStringAsFixed(1)} KB).\n"
          "Coba ulangi foto.",
        );
      }

      // ✅ 7) Upload ke Cloudinary
      final selfieUrl = await CloudinaryService.uploadImage(compressed);

      // ✅ 8) Simpan ke Firestore
      final now = DateTime.now();

      await docRef.set({
        "checkOutTime": now.toIso8601String(),
        "checkOutLat": pos.latitude,
        "checkOutLng": pos.longitude,
        "accuracyOut": pos.accuracy,
        "distanceOut": dist,
        "isMockDetectedOut": pos.isMocked,
        "checkOutSelfieUrl": selfieUrl,
        "checkOutStatus": "valid",
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("✅ Absen pulang berhasil")));

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  // ✅ Widget info box premium
  Widget infoBox(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cek status waktu untuk UI
    final bool earlyStatus = isTooEarly();
    final bool expiredStatus = isExpired();
    final bool cannotAbsen = earlyStatus || expiredStatus;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        title: const Text("Absen Pulang"),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ✅ CARD INFO
              Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Cek Lokasi & Selfie Pulang",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    infoBox(
                      "Waktu Absen",
                      "Mulai jam 15.00 s/d 23.59 WIB",
                      Icons.access_time_filled,
                      cannotAbsen ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(height: 12),
                    infoBox(
                      "Lokasi Kantor",
                      "Pastikan anda sudah di kantor KPU Provinsi Kepri",
                      Icons.location_on,
                      Colors.red,
                    ),
                    const SizedBox(height: 12),
                    infoBox(
                      "Radius",
                      "Maksimal radius 300m", // Sesuaikan dengan variabel radiusMeters (300)
                      Icons.my_location,
                      Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    if (debugInfo.isNotEmpty)
                      infoBox(
                        "Debug Info",
                        debugInfo,
                        Icons.info_outline,
                        Colors.deepPurple,
                      ),
                    if (selfiePreview != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        "Preview Selfie Pulang",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          selfiePreview!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ✅ BUTTON ABSEN PULANG
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // Tombol jadi abu-abu jika belum waktunya atau sudah lewat
                    backgroundColor: cannotAbsen
                        ? Colors.grey
                        : const Color(0xFF7A0C10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  // Disable tombol jika tidak bisa absen
                  onPressed: (_loading || cannotAbsen) ? null : checkOut,
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          earlyStatus
                              ? "⏳ Belum Waktu Pulang"
                              : expiredStatus
                              ? "❌ Batas Waktu Terlewati"
                              : "✅ Absen Pulang Sekarang",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              if (earlyStatus)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    "Absen pulang baru bisa dilakukan mulai pukul 15.00 WIB.",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              if (expiredStatus)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    "Hari telah berganti. Anda tidak dapat melakukan absen pulang untuk tanggal sebelumnya.",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

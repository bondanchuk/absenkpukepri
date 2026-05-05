import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import 'location_service.dart';
import 'cloudinary_service.dart';

class CheckInPage extends StatefulWidget {
  final String nip;
  const CheckInPage({super.key, required this.nip});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  bool _loading = false;

  // ✅ Koordinat Kantor
  final double officeLat = 0.8969112;
  final double officeLng = 104.4773251;
  final double radiusMeters = 300;

  String debugInfo = "";
  File? selfiePreview;

  // ✅ Fungsi Cek Belum Waktunya (Sebelum 06.00)
  bool isTooEarly() {
    final now = DateTime.now();
    final startTime = DateTime(now.year, now.month, now.day, 6, 0); // Jam 06:00
    return now.isBefore(startTime);
  }

  // ✅ Fungsi Cek Terlambat (Batas 09.00)
  bool isLate() {
    final now = DateTime.now();
    final deadline = DateTime(now.year, now.month, now.day, 9, 0); // Jam 09:00
    return now.isAfter(deadline);
  }

  String todayDocId() {
    final now = DateTime.now();
    return "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
  }

  Future<void> checkIn() async {
    // ✅ Validasi Waktu Sebelum Proses
    if (isTooEarly()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏳ Belum waktunya absen. Absen dimulai jam 06.00 WIB."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (isLate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Batas waktu absen masuk adalah jam 09.00 WIB."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // 1) Ambil lokasi
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

      // ✅ Validasi lokasi
      if (pos.accuracy > 25) {
        throw Exception(
          "Akurasi GPS terlalu buruk (${pos.accuracy.toStringAsFixed(1)}m).\n"
          "Coba lagi di tempat terbuka.",
        );
      }

      if (pos.isMocked) {
        throw Exception(
          "Mock Location terdeteksi.\n"
          "Matikan Fake GPS / Mock Location.",
        );
      }

      if (dist > radiusMeters) {
        throw Exception(
          "Di luar area kantor.\n"
          "Jarak: ${dist.toStringAsFixed(1)} m",
        );
      }

      // 2) Ambil selfie
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100,
      );

      if (picked == null) {
        throw Exception("Selfie wajib untuk absen masuk.");
      }

      final original = File(picked.path);
      setState(() => selfiePreview = original);

      // 3) Compress foto
      final compressed = await CloudinaryService.compressTo200KB(original);
      if (compressed == null) throw Exception("Gagal compress foto.");

      // 4) Upload ke Cloudinary
      final selfieUrl = await CloudinaryService.uploadImage(compressed);

      // 5) Simpan ke Firestore
      final now = DateTime.now();
      final dateStr = DateFormat("yyyy-MM-dd").format(now);
      final docId = todayDocId();

      final docRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(docId);

      final snapshot = await docRef.get();
      if (snapshot.exists && snapshot.data()?["checkInTime"] != null) {
        throw Exception("Kamu sudah absen masuk hari ini ✅");
      }

      await docRef.set({
        "nip": widget.nip,
        "date": dateStr,
        "checkInTime": now.toIso8601String(),
        "checkInLat": pos.latitude,
        "checkInLng": pos.longitude,
        "accuracyIn": pos.accuracy,
        "distanceIn": dist,
        "isMockDetectedIn": pos.isMocked,
        "checkInSelfieUrl": selfieUrl,
        "status": "valid",
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("✅ Absen masuk berhasil")));

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

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
    final bool lateStatus = isLate();
    final bool cannotAbsen = earlyStatus || lateStatus;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        title: const Text("Absen Masuk"),
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
                      "Mohon Perhatikan",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    infoBox(
                      "Waktu Absen",
                      "Mulai jam 06.00 s/d 09.00 WIB",
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
                      "Maksimal radius 300m",
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
                        "Preview Selfie",
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

              // ✅ BUTTON ABSEN MASUK
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // Tombol jadi abu-abu jika belum waktunya atau terlambat
                    backgroundColor: cannotAbsen
                        ? Colors.grey
                        : const Color(0xFF7A0C10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  // Disable tombol jika tidak bisa absen
                  onPressed: (_loading || cannotAbsen) ? null : checkIn,
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
                              ? "⏳ Belum Waktu Absen"
                              : lateStatus
                              ? "❌ Waktu Absen Berakhir"
                              : "✅ Absen Masuk Sekarang",
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
                    "Absen masuk baru bisa dilakukan mulai pukul 06.00 WIB.",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              if (lateStatus)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    "Sudah melewati jam 09.00. Hubungi Admin jika ada kendala.",
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

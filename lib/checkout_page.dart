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
  bool _isLoadingData = true;

  Map<String, dynamic>? _attendanceData;
  String? _activeDocId;

  final double officeLat = 0.8969112;
  final double officeLng = 104.4773251;
  final double radiusMeters = 350; // ✅ Diubah menjadi 350m

  File? selfiePreview;

  @override
  void initState() {
    super.initState();
    _fetchActiveAttendance();
  }

  // ✅ LOGIKA BARU: Jika belum absen masuk, tetap set _activeDocId untuk hari ini
  Future<void> _fetchActiveAttendance() async {
    try {
      final now = DateTime.now();
      final todayId = "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
      final yesterdayId =
          "${widget.nip}_${DateFormat("yyyyMMdd").format(now.subtract(const Duration(days: 1)))}";

      var todayDoc = await FirebaseFirestore.instance
          .collection("attendance")
          .doc(todayId)
          .get();
      var yesterdayDoc = await FirebaseFirestore.instance
          .collection("attendance")
          .doc(yesterdayId)
          .get();

      if (todayDoc.exists && todayDoc.data()?['checkOutTime'] == null) {
        // Sudah absen masuk hari ini, belum pulang
        _activeDocId = todayId;
        _attendanceData = todayDoc.data();
      } else if (yesterdayDoc.exists &&
          yesterdayDoc.data()?['checkOutTime'] == null &&
          yesterdayDoc.data()?['shift'] == 'Shift 3') {
        // Shift 3 kemarin malam, belum pulang
        _activeDocId = yesterdayId;
        _attendanceData = yesterdayDoc.data();
      } else if (todayDoc.exists && todayDoc.data()?['checkOutTime'] != null) {
        // Sudah pulang hari ini
        _activeDocId = null;
      } else {
        // BELUM ABSEN MASUK SAMA SEKALI
        // Tetap izinkan untuk absen pulang (Dokumen akan dibuat saat disubmit)
        _activeDocId = todayId;
        _attendanceData = null;
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  // ✅ WAKTU MINIMAL BOLEH PULANG
  bool isTooEarly() {
    final now = DateTime.now();
    // Jika _attendanceData null, otomatis dianggap Non-Shift (Bukan Security)
    final shift = _attendanceData?['shift'] ?? "Non-Shift";

    if (shift == "Shift 1") {
      return now.isBefore(DateTime(now.year, now.month, now.day, 15, 0));
    }
    if (shift == "Shift 2") {
      return now.isBefore(DateTime(now.year, now.month, now.day, 23, 0));
    }
    if (shift == "Shift 3") return now.hour < 7;

    // Pegawai Biasa (Non-Shift) atau belum absen masuk -> Boleh pulang mulai jam 15.00
    return now.isBefore(DateTime(now.year, now.month, now.day, 15, 0));
  }

  Future<void> checkOut() async {
    if (_activeDocId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Anda sudah absen pulang hari ini."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (isTooEarly()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏳ Belum waktunya absen pulang."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(_activeDocId);

      // Cek mode WFH: Jika belum absen masuk & hari ini Jumat, otomatis bebas radius
      bool isWfh = _attendanceData?['workMode'] == "WFH";
      bool isFriday = DateTime.now().weekday == DateTime.friday;
      if (_attendanceData == null && isFriday) {
        isWfh = true;
      }

      double lat = 0.0;
      double lng = 0.0;
      double dist = 0.0;

      // ✅ Lakukan pengecekan GPS HANYA JIKA BUKAN WFH (Selain Jumat)
      if (!isWfh) {
        final pos = await LocationService.getCurrentPosition();
        dist = LocationService.distanceInMeters(
          pos.latitude,
          pos.longitude,
          officeLat,
          officeLng,
        );

        if (pos.accuracy > 25) throw Exception("Akurasi GPS terlalu buruk.");
        if (pos.isMocked) throw Exception("Fake GPS terdeteksi.");

        if (dist > radiusMeters) {
          throw Exception(
            "Di luar area kantor.\nJarak: ${dist.toStringAsFixed(1)} m",
          );
        }

        lat = pos.latitude;
        lng = pos.longitude;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100,
      );
      if (picked == null) throw Exception("Selfie wajib untuk absen pulang.");

      final original = File(picked.path);
      setState(() => selfiePreview = original);

      final compressed = await CloudinaryService.compressTo200KB(original);
      if (compressed == null) throw Exception("Gagal compress foto.");

      final selfieUrl = await CloudinaryService.uploadImage(compressed);
      final now = DateTime.now();

      // ✅ Gunakan SetOptions(merge: true) agar jika dokumen belum ada (tidak absen masuk),
      // Firebase akan otomatis membuatnya, lengkap dengan NIP dan Date.
      await docRef.set({
        "nip": widget.nip,
        "date": DateFormat("yyyy-MM-dd").format(now),
        "checkOutTime": now.toIso8601String(),
        "checkOutLat": lat,
        "checkOutLng": lng,
        "distanceOut": dist,
        "checkOutSelfieUrl": selfieUrl,
        "updatedAt": FieldValue.serverTimestamp(),
        "workMode": isWfh ? "WFH" : "WFO",
        "shift": _attendanceData?['shift'] ?? "Non-Shift",
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

  String getTimeInfoText() {
    final shift = _attendanceData?['shift'] ?? "Non-Shift";
    if (shift == "Shift 2") return "Pulang mulai 23.00 WIB";
    if (shift == "Shift 3") return "Pulang mulai 07.00 WIB (Pagi)";
    return "Pulang mulai 15.00 WIB";
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
    if (_isLoadingData) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7A0C10)),
        ),
      );
    }

    final bool earlyStatus = isTooEarly();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        title: const Text("Absen Pulang"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _attendanceData == null
                        ? "Status: Tidak ada Absen Masuk"
                        : "Jadwal: ${_attendanceData!['shift']}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7A0C10),
                    ),
                  ),
                  if (_attendanceData == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        "Anda bisa langsung absen pulang meskipun belum absen masuk hari ini.",
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 14),
                  infoBox(
                    "Waktu Absen Pulang",
                    getTimeInfoText(),
                    Icons.access_time_filled,
                    earlyStatus ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(height: 12),
                  infoBox(
                    _attendanceData?['workMode'] == "WFH"
                        ? "Mode WFH Aktif"
                        : "Lokasi & Radius",
                    _attendanceData?['workMode'] == "WFH"
                        ? "Radius bebas"
                        : "Maksimal radius 350m", // ✅ Tulisan disesuaikan
                    _attendanceData?['workMode'] == "WFH"
                        ? Icons.home_work
                        : Icons.my_location,
                    Colors.blue,
                  ),
                  if (selfiePreview != null) ...[
                    const SizedBox(height: 16),
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
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_activeDocId == null || earlyStatus)
                      ? Colors.grey
                      : const Color(0xFF7A0C10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: (_loading || _activeDocId == null || earlyStatus)
                    ? null
                    : checkOut,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        earlyStatus
                            ? "⏳ Belum Waktu Pulang"
                            : "✅ Absen Pulang Sekarang",
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
    );
  }
}

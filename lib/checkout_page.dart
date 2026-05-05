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
  final double radiusMeters = 300;

  File? selfiePreview;

  @override
  void initState() {
    super.initState();
    _fetchActiveAttendance();
  }

  // ✅ MENCARI DATA ABSEN MASUK YANG BELUM PULANG
  Future<void> _fetchActiveAttendance() async {
    try {
      final now = DateTime.now();
      final todayId = "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
      final yesterdayId =
          "${widget.nip}_${DateFormat("yyyyMMdd").format(now.subtract(const Duration(days: 1)))}";

      // Cek doc hari ini
      var doc = await FirebaseFirestore.instance
          .collection("attendance")
          .doc(todayId)
          .get();
      if (doc.exists && doc.data()?['checkOutTime'] == null) {
        _activeDocId = todayId;
        _attendanceData = doc.data();
      } else {
        // Cek doc kemarin (Khusus Security Shift 3 yang pulangnya pagi)
        doc = await FirebaseFirestore.instance
            .collection("attendance")
            .doc(yesterdayId)
            .get();
        if (doc.exists && doc.data()?['checkOutTime'] == null) {
          _activeDocId = yesterdayId;
          _attendanceData = doc.data();
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  // ✅ WAKTU MINIMAL BOLEH PULANG (DINAMIS DARI SHIFT)
  bool isTooEarly() {
    final now = DateTime.now();
    final shift = _attendanceData?['shift'] ?? "Non-Shift";

    if (shift == "Shift 1")
      return now.isBefore(
        DateTime(now.year, now.month, now.day, 15, 0),
      ); // Pulang jam 15.00
    if (shift == "Shift 2")
      return now.isBefore(
        DateTime(now.year, now.month, now.day, 23, 0),
      ); // Pulang jam 23.00
    if (shift == "Shift 3")
      return now.hour < 7; // Pulang keesokan harinya jam 07.00 pagi

    // Pegawai Biasa
    return now.isBefore(
      DateTime(now.year, now.month, now.day, 15, 0),
    ); // Pulang jam 15.00
  }

  Future<void> checkOut() async {
    if (_activeDocId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Data absen masuk tidak ditemukan/Sudah pulang."),
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
      final pos = await LocationService.getCurrentPosition();
      final dist = LocationService.distanceInMeters(
        pos.latitude,
        pos.longitude,
        officeLat,
        officeLng,
      );

      if (pos.accuracy > 25) throw Exception("Akurasi GPS terlalu buruk.");
      if (pos.isMocked) throw Exception("Fake GPS terdeteksi.");

      // Cek apakah mode WFH (Ditarik dari data absen masuk)
      bool isWfh = _attendanceData?['workMode'] == "WFH";
      if (!isWfh && dist > radiusMeters) {
        throw Exception(
          "Di luar area kantor.\nJarak: ${dist.toStringAsFixed(1)} m",
        );
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

      await docRef.set({
        "checkOutTime": DateTime.now().toIso8601String(),
        "checkOutLat": pos.latitude,
        "checkOutLng": pos.longitude,
        "distanceOut": dist,
        "checkOutSelfieUrl": selfieUrl,
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

    final bool earlyStatus = _attendanceData != null && isTooEarly();

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
                        ? "Status Absen"
                        : "Jadwal: ${_attendanceData!['shift']}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7A0C10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  infoBox(
                    "Waktu Absen Pulang",
                    _attendanceData == null
                        ? "Belum ada data masuk"
                        : getTimeInfoText(),
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
                        : "Maksimal radius 300m",
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
                  backgroundColor: (earlyStatus || _attendanceData == null)
                      ? Colors.grey
                      : const Color(0xFF7A0C10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: (_loading || earlyStatus || _attendanceData == null)
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

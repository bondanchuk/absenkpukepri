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

  // ✅ Variabel penampung status WFH Dinamis
  bool isWfhToday = false;

  // ✅ Mengubah variabel koordinat menjadi dinamis (Akan dimuat dari Firestore)
  double officeLat = 0.8969112;
  double officeLng = 104.4773251;
  double radiusMeters = 350;
  String officeName = "Area Kantor";

  File? selfiePreview;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // ✅ Menjalankan pengecekan secara berurutan saat halaman dibuka
  Future<void> _initializeApp() async {
    await _checkWfhStatus();
    await _fetchLocationConfig(); // ✅ Mengambil konfigurasi koordinat dari database admin
    await _fetchActiveAttendance();
  }

  // ✅ FUNGSI BARU: MENGAMBIL TITIK KOORDINAT DINAMIS DARI FIRESTORE
  Future<void> _fetchLocationConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("settings")
          .doc("location_config")
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            officeLat = (data['latitude'] as num).toDouble();
            officeLng = (data['longitude'] as num).toDouble();
            radiusMeters = (data['radius'] as num).toDouble();
            officeName = data['location_name'] ?? "Area Kantor";
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal memuat konfigurasi lokasi checkout: $e");
    }
  }

  Future<void> _checkWfhStatus() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("settings")
          .doc("wfh_config")
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        List<dynamic> wfhDays = data['wfh_days'] ?? [];
        List<dynamic> wfhDates = data['wfh_dates'] ?? [];

        final now = DateTime.now();
        final todayString = DateFormat("yyyy-MM-dd").format(now);

        if (wfhDays.contains(now.weekday) || wfhDates.contains(todayString)) {
          if (mounted) {
            setState(() {
              isWfhToday = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Gagal cek WFH status: $e");
    }
  }

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
        _activeDocId = todayId;
        _attendanceData = todayDoc.data();
      } else if (yesterdayDoc.exists &&
          yesterdayDoc.data()?['checkOutTime'] == null &&
          yesterdayDoc.data()?['shift'] == 'Shift 3') {
        _activeDocId = yesterdayId;
        _attendanceData = yesterdayDoc.data();
      } else if (todayDoc.exists && todayDoc.data()?['checkOutTime'] != null) {
        _activeDocId = null;
      } else {
        _activeDocId = todayId;
        _attendanceData = null;
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  bool isOutsideCheckOutTime() {
    final now = DateTime.now();
    final shift = _attendanceData?['shift'] ?? "Non-Shift";

    if (shift == "Shift 1") return now.hour < 15;
    if (shift == "Shift 2") return now.hour < 23;
    if (shift == "Shift 3") return now.hour >= 7;

    if (now.hour < 15) return true;

    return false;
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

    if (isOutsideCheckOutTime()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏳ Anda berada di luar jam absen pulang."),
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

      bool isWfhMode = (_attendanceData?['workMode'] == "WFH") || isWfhToday;

      double lat = 0.0;
      double lng = 0.0;
      double dist = 0.0;

      if (!isWfhMode) {
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
            "Anda berada di luar $officeName.\nJarak Anda: ${dist.toStringAsFixed(1)} meter (Batas: ${radiusMeters.toStringAsFixed(0)}m)",
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

      await docRef.set({
        "nip": widget.nip,
        "date": DateFormat("yyyy-MM-dd").format(now),
        "checkOutTime": now.toIso8601String(),
        "checkOutLat": lat,
        "checkOutLng": lng,
        "distanceOut": dist,
        "checkOutSelfieUrl": selfieUrl,
        "updatedAt": FieldValue.serverTimestamp(),
        "workMode": isWfhMode ? "WFH" : "WFO",
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
      if (mounted) setState(() => _loading = false);
    }
  }

  String getTimeInfoText() {
    final shift = _attendanceData?['shift'] ?? "Non-Shift";
    if (shift == "Shift 2") return "Pulang mulai 23.00 WIB";
    if (shift == "Shift 3") return "Pulang sebelum 07.00 WIB";
    return "15.00 - 23.59 WIB";
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

    final bool cannotAbsen = isOutsideCheckOutTime();
    bool isWfhMode = (_attendanceData?['workMode'] == "WFH") || isWfhToday;

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
                    "Waktu Kehadiran",
                    getTimeInfoText(),
                    Icons.access_time_filled,
                    cannotAbsen ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(height: 12),

                  infoBox(
                    isWfhMode ? "Mode WFH Aktif" : "Lokasi & Radius",
                    isWfhMode ? "Tanpa akses GPS / Lokasi" : "$officeName",
                    isWfhMode ? Icons.location_off : Icons.my_location,
                    isWfhMode ? Colors.green : Colors.blue,
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
                  backgroundColor: (_activeDocId == null || cannotAbsen)
                      ? Colors.grey
                      : const Color(0xFF7A0C10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: (_loading || _activeDocId == null || cannotAbsen)
                    ? null
                    : checkOut,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        cannotAbsen
                            ? "❌ Di Luar Waktu Pulang"
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

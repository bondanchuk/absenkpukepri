import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import 'location_service.dart';
import 'cloudinary_service.dart';

class CheckInPage extends StatefulWidget {
  final String nip;
  // Hapus required positions agar tidak error dari HomePage
  const CheckInPage({super.key, required this.nip});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  bool _loading = false;
  bool _isLoadingData = true; // Untuk loading ambil data user
  bool _isSecurity = false;

  String? selectedShift;
  String debugInfo = "";
  File? selfiePreview;

  // Koordinat Kantor
  final double officeLat = 0.8969112;
  final double officeLng = 104.4773251;
  final double radiusMeters = 300;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // ✅ AMBIL JABATAN DARI FIRESTORE SECARA LANGSUNG
  Future<void> _fetchUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.nip)
          .get();
      if (doc.exists) {
        String pos = (doc.data()?['positions'] ?? "").toString().toLowerCase();
        bool sec =
            pos.contains('security') ||
            pos.contains('satpam') ||
            pos.contains('keamanan');

        setState(() {
          _isSecurity = sec;
          if (sec) selectedShift = "Shift 1"; // Default awal
        });
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  bool get isFriday {
    return DateTime.now().weekday == DateTime.friday;
  }

  // ✅ CEK BELUM WAKTUNYA
  bool isTooEarly() {
    final now = DateTime.now();
    if (_isSecurity) {
      if (selectedShift == "Shift 1")
        return now.isBefore(DateTime(now.year, now.month, now.day, 6, 0));
      if (selectedShift == "Shift 2")
        return now.isBefore(DateTime(now.year, now.month, now.day, 14, 0));
      if (selectedShift == "Shift 3")
        return now.isBefore(DateTime(now.year, now.month, now.day, 22, 0));
    }
    return now.isBefore(
      DateTime(now.year, now.month, now.day, 6, 0),
    ); // Pegawai Biasa
  }

  // ✅ CEK TERLAMBAT
  bool isLate() {
    final now = DateTime.now();
    if (_isSecurity) {
      if (selectedShift == "Shift 1")
        return now.isAfter(DateTime(now.year, now.month, now.day, 8, 30));
      if (selectedShift == "Shift 2")
        return now.isAfter(DateTime(now.year, now.month, now.day, 15, 30));
      if (selectedShift == "Shift 3")
        return false; // Karena batasnya 23:59, hari ini tidak mungkin lewat 23:59
    }
    return now.isAfter(
      DateTime(now.year, now.month, now.day, 9, 0),
    ); // Pegawai Biasa
  }

  String todayDocId() {
    final now = DateTime.now();
    return "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
  }

  Future<void> checkIn() async {
    if (isTooEarly()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏳ Belum waktunya absen masuk."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (isLate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Batas waktu absen masuk telah berakhir."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final pos = await LocationService.getCurrentPosition();
      final dist = LocationService.distanceInMeters(
        pos.latitude,
        pos.longitude,
        officeLat,
        officeLng,
      );

      setState(() {
        debugInfo =
            "Distance: ${dist.toStringAsFixed(1)} m\nMocked: ${pos.isMocked}";
      });

      if (pos.accuracy > 25)
        throw Exception("Akurasi GPS terlalu buruk. Coba di tempat terbuka.");
      if (pos.isMocked) throw Exception("Fake GPS terdeteksi.");

      bool isWfhValid = isFriday && !_isSecurity;
      if (!isWfhValid && dist > radiusMeters) {
        throw Exception(
          "Di luar area kantor.\nJarak Anda: ${dist.toStringAsFixed(1)} m",
        );
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100,
      );
      if (picked == null) throw Exception("Selfie wajib untuk absen masuk.");

      final original = File(picked.path);
      setState(() => selfiePreview = original);

      final compressed = await CloudinaryService.compressTo200KB(original);
      if (compressed == null) throw Exception("Gagal compress foto.");

      final selfieUrl = await CloudinaryService.uploadImage(compressed);
      final now = DateTime.now();
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
        "date": DateFormat("yyyy-MM-dd").format(now),
        "checkInTime": now.toIso8601String(),
        "checkInLat": pos.latitude,
        "checkInLng": pos.longitude,
        "distanceIn": dist,
        "checkInSelfieUrl": selfieUrl,
        "workMode": isWfhValid ? "WFH" : "WFO",
        "shift": _isSecurity ? selectedShift : "Non-Shift",
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

  String getTimeInfoText() {
    if (_isSecurity) {
      if (selectedShift == "Shift 1") return "06.00 s/d 08.30 WIB";
      if (selectedShift == "Shift 2") return "14.00 s/d 15.30 WIB";
      if (selectedShift == "Shift 3") return "22.00 s/d 23.59 WIB";
    }
    return "06.00 s/d 09.00 WIB";
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
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
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

    final bool cannotAbsen = isTooEarly() || isLate();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        title: const Text("Absen Masuk"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isSecurity) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF7A0C10),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Pilih Shift Anda",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF7A0C10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedShift,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: ["Shift 1", "Shift 2", "Shift 3"]
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => selectedShift = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Mohon Perhatikan",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  infoBox(
                    "Batas Waktu Masuk",
                    getTimeInfoText(),
                    Icons.access_time_filled,
                    cannotAbsen ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(height: 12),
                  infoBox(
                    isFriday && !_isSecurity
                        ? "Mode WFH Aktif"
                        : "Lokasi & Radius",
                    isFriday && !_isSecurity
                        ? "Hari Jumat: WFH Diizinkan"
                        : "Maksimal radius 300m dari KPU",
                    isFriday && !_isSecurity
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
                  backgroundColor: cannotAbsen
                      ? Colors.grey
                      : const Color(0xFF7A0C10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: (_loading || cannotAbsen) ? null : checkIn,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        cannotAbsen
                            ? "❌ Di Luar Waktu Absen"
                            : "✅ Absen Masuk Sekarang",
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

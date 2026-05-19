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
  final double radiusMeters = 350; // ✅ Diubah menjadi 350m

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // ✅ AMBIL JABATAN DARI FIRESTORE SECARA LANGSUNG
  Future<void> _fetchUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.nip)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final posisi = data["positions"]?.toString().toLowerCase() ?? "";
        if (posisi.contains("satpam") || posisi.contains("security")) {
          _isSecurity = true;
          // Set default shift ke Shift 1 agar dropdown ada nilai awal
          selectedShift = "Shift 1";
        }
      }
    } catch (e) {
      debugPrint("Gagal mengambil data jabatan: $e");
    } finally {
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  // Cek jika Security, dan belum jam absen sesuai shift
  bool isSecurityAndOutsideShift() {
    if (!_isSecurity || selectedShift == null) return false;

    final now = DateTime.now();
    // Jam 06.00 - 08.00 pagi
    if (selectedShift == "Shift 1") {
      return now.hour < 6 || now.hour >= 8;
    }
    // Jam 14.00 - 16.00 sore
    if (selectedShift == "Shift 2") {
      return now.hour < 14 || now.hour >= 16;
    }
    // Jam 22.00 - 23.59 malam
    if (selectedShift == "Shift 3") {
      return now.hour < 22; // Asumsi maksimal 23:59 tidak perlu batas atas jam
    }

    return false;
  }

  Future<void> checkIn() async {
    if (isSecurityAndOutsideShift()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Anda tidak bisa absen di luar jam shift."),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      bool isFriday = DateTime.now().weekday == DateTime.friday;
      bool isWfh = isFriday; // WFH jika hari Jumat

      double lat = 0.0;
      double lng = 0.0;
      double dist = 0.0;

      // ✅ Lakukan pengecekan GPS HANYA JIKA BUKAN WFH (Selain Jumat)
      // Jika WFH, sistem tidak akan menyalakan/memeriksa GPS
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
            "Anda berada di luar area kantor.\nJarak Anda: ${dist.toStringAsFixed(1)} meter",
          );
        }

        lat = pos.latitude;
        lng = pos.longitude;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100, // Menjaga kualitas terbaik dari kamera
      );
      if (picked == null) throw Exception("Selfie wajib untuk absen.");

      final originalFile = File(picked.path);
      setState(() => selfiePreview = originalFile);

      // ✅ COMPRESS GAMBAR SEBELUM UPLOAD
      final compressedFile = await CloudinaryService.compressTo200KB(
        originalFile,
      );
      if (compressedFile == null) {
        throw Exception("Gagal mengompres gambar.");
      }

      final selfieUrl = await CloudinaryService.uploadImage(compressedFile);

      final now = DateTime.now();
      final docId = "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
      final docRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(docId);

      final existingDoc = await docRef.get();
      if (existingDoc.exists && existingDoc.data()?['checkInTime'] != null) {
        throw Exception("Anda sudah absen masuk hari ini.");
      }

      await docRef.set({
        "nip": widget.nip,
        "date": DateFormat("yyyy-MM-dd").format(now),
        "checkInTime": now.toIso8601String(),
        "checkInLat": lat,
        "checkInLng": lng,
        "distanceIn": dist,
        "workMode": isWfh ? "WFH" : "WFO",
        "checkInSelfieUrl": selfieUrl,
        "shift": _isSecurity
            ? selectedShift
            : "Non-Shift", // Simpan shift jika security
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("✅ Absen masuk berhasil")));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
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
    if (_isLoadingData) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7A0C10)),
        ),
      );
    }

    bool isFriday = DateTime.now().weekday == DateTime.friday;
    bool isWfh = isFriday;

    bool cannotAbsen = isSecurityAndOutsideShift();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          "Absen Masuk",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        elevation: 0,
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
                  Text(
                    _isSecurity ? "Jadwal Shift" : "Jadwal Reguler",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7A0C10),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ✅ Jika Security, tampilkan Dropdown Shift
                  if (_isSecurity) ...[
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
                          value: selectedShift,
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Color(0xFF7A0C10),
                          ),
                          items: ["Shift 1", "Shift 2", "Shift 3"]
                              .map(
                                (shift) => DropdownMenuItem(
                                  value: shift,
                                  child: Text(
                                    shift,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedShift = val;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    infoBox(
                      "Waktu Shift",
                      selectedShift == "Shift 1"
                          ? "06.00 - 08.00 WIB"
                          : selectedShift == "Shift 2"
                          ? "14.00 - 16.00 WIB"
                          : "22.00 - 23.59 WIB",
                      Icons.access_time_filled,
                      cannotAbsen ? Colors.red : Colors.green,
                    ),
                  ] else ...[
                    // Jika Reguler, hanya tampilkan teks tanpa dropdown
                    infoBox(
                      "Waktu Absen",
                      "06.00 - 08.00 WIB",
                      Icons.access_time_filled,
                      Colors.green,
                    ),
                  ],

                  const SizedBox(height: 12),
                  infoBox(
                    isWfh ? "Mode WFH Aktif" : "Lokasi & Radius",
                    isWfh
                        ? "Radius bebas"
                        : "Maksimal radius 350m", // ✅ Tulisan disesuaikan
                    isWfh ? Icons.home_work : Icons.my_location,
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

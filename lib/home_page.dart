import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_page.dart';
import 'checkin_page.dart';
import 'checkout_page.dart';
import 'report_page.dart';
import 'attendance_history_page.dart';
import 'pengajuan_page.dart';

class HomePage extends StatefulWidget {
  final String nip;
  final String name;

  const HomePage({super.key, required this.nip, required this.name});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;
  String _currentTime = "";

  // ✅ Variabel penampung status WFH Dinamis
  bool isWfhToday = false;

  @override
  void initState() {
    super.initState();
    _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );

    // Panggil fungsi cek WFH saat halaman dimuat
    _checkWfhStatus();
  }

  // ✅ FUNGSI BACA PENGATURAN WFH DARI FIRESTORE
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

        // Cek apakah hari (1-7) atau tanggal (yyyy-mm-dd) cocok
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

  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            "Konfirmasi Logout",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Color(0xFF7A0C10),
            ),
          ),
          content: const Text(
            "Apakah Anda yakin ingin keluar dari aplikasi?",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Batal",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A0C10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();

                if (!mounted) return;

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
              child: const Text(
                "Keluar",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  String getGreeting() {
    var hour = DateTime.now().hour;
    if (hour < 11) return "Selamat Pagi,";
    if (hour < 15) return "Selamat Siang,";
    if (hour < 18) return "Selamat Sore,";
    return "Selamat Malam,";
  }

  String todayDocId() {
    final now = DateTime.now();
    return "${widget.nip}_${DateFormat("yyyyMMdd").format(now)}";
  }

  String todayLabel() {
    final now = DateTime.now();
    return DateFormat("EEEE, dd MMMM yyyy", "id_ID").format(now);
  }

  @override
  Widget build(BuildContext context) {
    final docId = todayDocId();
    final attendanceRef = FirebaseFirestore.instance
        .collection("attendance")
        .doc(docId);
    final userRef = FirebaseFirestore.instance
        .collection("users")
        .doc(widget.nip);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: StreamBuilder<DocumentSnapshot>(
        stream: attendanceRef.snapshots(),
        builder: (context, snapshot) {
          bool sudahMasuk = false;
          bool sudahPulang = false;
          bool sudahReport = false;

          bool isLeaveDay = false;
          String leaveStatus = "";

          String masukJam = "-";
          String pulangJam = "-";
          String reportStatus = "-";

          // Gunakan status WFH dari _checkWfhStatus, namun periksa juga history database
          bool isWfhMode = isWfhToday;

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;

            if (data['status'] != null &&
                data['status'] != 'Hadir' &&
                data['status'] != 'valid') {
              isLeaveDay = true;
              leaveStatus = data['status'];
            }

            // Cek apakah database hari ini merekam mode kerja "WFH"
            if (data['workMode'] == 'WFH') {
              isWfhMode = true;
            }

            if (data["checkInTime"] != null) {
              sudahMasuk = true;
              masukJam = DateFormat(
                "HH:mm",
              ).format(DateTime.parse(data["checkInTime"]));
            }
            if (data["checkOutTime"] != null) {
              sudahPulang = true;
              pulangJam = DateFormat(
                "HH:mm",
              ).format(DateTime.parse(data["checkOutTime"]));
            }
            if (data["performanceReport"] != null) {
              sudahReport = true;
              reportStatus = "Sudah diisi ✅";
            }
          }

          int currentHour = DateTime.now().hour;
          bool isTimeForCheckout = currentHour >= 15;
          bool isTimeForReport = currentHour >= 17;

          if (isLeaveDay) {
            reportStatus = "Tidak wajib (Sedang $leaveStatus)";
          } else if (!sudahReport) {
            if (!sudahPulang) {
              reportStatus = isTimeForReport
                  ? "Bisa diisi (Tanpa pulang)"
                  : "Isi setelah pulang";
            } else {
              reportStatus = "Isi laporan hari ini";
            }
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                // ✅ Tinggi diturunkan menjadi 145 agar tidak ada ruang kosong berlebih di bawah
                expandedHeight: 125,
                backgroundColor: const Color(0xFF7A0C10),
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  background: Padding(
                    padding: const EdgeInsets.fromLTRB(25, 52, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                getGreeting(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                widget.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              StreamBuilder<DocumentSnapshot>(
                                stream: userRef.snapshots(),
                                builder: (context, userSnap) {
                                  String jabatan = "NIP: ${widget.nip}";
                                  if (userSnap.hasData &&
                                      userSnap.data!.exists) {
                                    final userData =
                                        userSnap.data!.data()
                                            as Map<String, dynamic>;
                                    String pos = userData["positions"] ?? "-";
                                    jabatan = "$pos | NIP: ${widget.nip}";
                                  }
                                  return Text(
                                    jabatan,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white70,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    todayLabel(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "$_currentTime WIB",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showLogoutDialog(context),
                          icon: const Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                  child: Column(
                    children: [
                      if (isLeaveDay)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.orange,
                                size: 30,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  "Anda tercatat sedang $leaveStatus hari ini. Fitur absensi normal dinonaktifkan sementara.",
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (isWfhMode)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.home_work,
                                color: Colors.green,
                                size: 30,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  "Hari ini WFH",
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      _premiumCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Status Kehadiran",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _statusTile(
                                      title: "Masuk",
                                      subtitle: isLeaveDay
                                          ? leaveStatus
                                          : (sudahMasuk ? masukJam : "Belum"),
                                      icon: Icons.login,
                                      active: sudahMasuk || isLeaveDay,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _statusTile(
                                      title: "Pulang",
                                      subtitle: isLeaveDay
                                          ? leaveStatus
                                          : (sudahPulang ? pulangJam : "Belum"),
                                      icon: Icons.logout,
                                      active: sudahPulang || isLeaveDay,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _statusTile(
                                title: "Laporan Kinerja",
                                subtitle: reportStatus,
                                icon: Icons.assignment,
                                active: sudahReport || isLeaveDay,
                                color: Colors.orange,
                                fullWidth: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _premiumCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Menu Utama",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: PremiumMenuButton(
                                      icon: Icons.login,
                                      label: "Absen Masuk",
                                      enabled: !sudahMasuk && !isLeaveDay,
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CheckInPage(nip: widget.nip),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: PremiumMenuButton(
                                      icon: Icons.logout,
                                      label: "Absen Pulang",
                                      enabled:
                                          !sudahPulang &&
                                          (sudahMasuk || isTimeForCheckout) &&
                                          !isLeaveDay,
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CheckOutPage(nip: widget.nip),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              PremiumMenuButtonWide(
                                icon: Icons.assignment,
                                label: "Laporan Kinerja",
                                subtitle: isLeaveDay
                                    ? "Otomatis diisi sistem"
                                    : (sudahReport
                                          ? "Sudah dikirim ✅"
                                          : (sudahPulang
                                                ? "Isi laporan hari ini"
                                                : (isTimeForReport
                                                      ? "Isi sekarang (Lupa pulang)"
                                                      : "Isi setelah pulang"))),
                                enabled:
                                    !sudahReport &&
                                    (sudahPulang || isTimeForReport) &&
                                    !isLeaveDay,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReportPage(
                                        nip: widget.nip,
                                        docId: docId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _menuWideButton(
                        icon: Icons.edit_document,
                        label: isLeaveDay
                            ? "Pengajuan (Sudah Diajukan)"
                            : "Pengajuan Izin / Dinas",
                        enabled: !isLeaveDay,
                        colorStart: const Color(0xFFE67E22),
                        colorEnd: const Color(0xFFD35400),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PengajuanPage(
                                nip: widget.nip,
                                name: widget.name,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _menuWideButton(
                        icon: Icons.history,
                        label: "Riwayat Absensi",
                        enabled: true,
                        colorStart: const Color(0xFF7A0C10),
                        colorEnd: const Color(0xFFB31217),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AttendanceHistoryPage(
                                nip: widget.nip,
                                name: widget.name,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "KPU PROVINSI KEPRI",
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "BONDANCH@2026",
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _premiumCard({required Widget child}) {
    return Container(
      width: double.infinity,
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

  // Cari fungsi _statusTile di bagian bawah file home_page.dart Anda
  // Lalu ganti dengan kode di bawah ini:

  Widget _statusTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool active,
    required Color color,
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 10,
      ), // ✅ Padding diperkecil (sebelumnya 12-16)
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12), // ✅ Radius diperkecil sedikit
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16, // ✅ Ukuran lingkaran icon diperkecil (sebelumnya 20-22)
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 16), // ✅ Icon diperkecil
          ),
          const SizedBox(width: 6), // ✅ Jarak icon ke teks dipersempit
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize:
                        14, // ✅ Font "Masuk" diperkecil (sebelumnya 13-14)
                  ),
                  maxLines: 1,
                  overflow: TextOverflow
                      .visible, // ✅ Biarkan teks terlihat jika sedikit melebihi
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13, // ✅ Font Jam diperkecil (sebelumnya 12)
                    color: active ? Colors.black87 : Colors.black54,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (active) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 14,
            ), // ✅ Icon centang diperkecil
          ],
        ],
      ),
    );
  }
}

class PremiumMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const PremiumMenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = enabled ? const Color(0xFF1565C0) : Colors.grey.shade400;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 115, // ✅ Diturunkan menjadi 115 agar proporsional
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumMenuButtonWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const PremiumMenuButtonWide({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = enabled ? const Color(0xFF1565C0) : Colors.grey.shade400;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16), // ✅ Padding dikembalikan ke 16
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white.withOpacity(0.25),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6), // ✅ Sedikit dirapatkan
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _menuWideButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  required Color colorStart,
  required Color colorEnd,
  bool enabled = true,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: enabled ? onTap : null,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ), // ✅ Padding dikembalikan agar tidak kelonggaran
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enabled
              ? [colorStart, colorEnd]
              : [Colors.grey.shade400, Colors.grey.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (enabled)
            const Icon(Icons.chevron_right, color: Colors.white, size: 28),
        ],
      ),
    ),
  );
}

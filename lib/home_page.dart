import 'dart:async'; // ✅ Tambahan untuk fitur Jam Real-time
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'session_service.dart';
import 'login_page.dart';
import 'checkin_page.dart';
import 'checkout_page.dart';
import 'report_page.dart';
import 'attendance_history_page.dart';

class HomePage extends StatefulWidget {
  final String nip;
  final String name;

  const HomePage({super.key, required this.nip, required this.name});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ✅ Variabel untuk Jam Real-time
  Timer? _timer;
  String _currentTime = "";

  @override
  void initState() {
    super.initState();
    // Mengaktifkan Jam Real-time saat halaman dibuka
    _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );
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
    _timer
        ?.cancel(); // Mematikan timer saat halaman ditutup agar tidak memory leak
    super.dispose();
  }

  // ✅ Fungsi untuk Sapaan Dinamis
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

          String masukJam = "-";
          String pulangJam = "-";
          String reportStatus = "-";

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;

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

          if (!sudahPulang) {
            sudahReport = false;
            reportStatus = "Isi setelah pulang";
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ✅ HEADER MAROON
              SliverAppBar(
                pinned: true,
                expandedHeight:
                    140, // ✅ Sedikit dinaikkan untuk menampung Jam Real-time
                backgroundColor: const Color(0xFF7A0C10),
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  background: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ✅ SAPAAN PAGI/SIANG/MALAM
                              Text(
                                getGreeting(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 18,
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white70,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              // ✅ TANGGAL DAN JAM BERDETAK
                              Row(
                                children: [
                                  Text(
                                    todayLabel(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "$_currentTime WIB",
                                      style: const TextStyle(
                                        fontSize: 11,
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
                          onPressed: () async {
                            await SessionService.clearSession();
                            if (!mounted) return;
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.logout, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ✅ BODY CONTENT
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                  child: Column(
                    children: [
                      // ✅ STATUS CARD
                      _premiumCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Status Hari Ini",
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
                                      title: "Masuk", // ✅ Teks Dipendekkan
                                      subtitle: sudahMasuk
                                          ? masukJam // ✅ Jam Saja agar muat
                                          : "Belum absen",
                                      icon: Icons.login,
                                      active: sudahMasuk,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _statusTile(
                                      title: "Pulang", // ✅ Teks Dipendekkan
                                      subtitle: sudahPulang
                                          ? pulangJam // ✅ Jam Saja agar muat
                                          : "Belum absen",
                                      icon: Icons.logout,
                                      active: sudahPulang,
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
                                active: sudahReport,
                                color: Colors.orange,
                                fullWidth: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ✅ MENU UTAMA
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
                                      enabled: !sudahMasuk,
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: PremiumMenuButton(
                                      icon: Icons.logout,
                                      label: "Absen Pulang",
                                      enabled: sudahMasuk && !sudahPulang,
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
                              const SizedBox(height: 12),
                              PremiumMenuButtonWide(
                                icon: Icons.assignment,
                                label: "Laporan Kinerja",
                                subtitle: sudahReport
                                    ? "Sudah dikirim ✅"
                                    : (sudahPulang
                                          ? "Isi laporan hari ini"
                                          : "Isi setelah pulang"),
                                enabled: sudahPulang && !sudahReport,
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

                      // ✅ RIWAYAT ABSENSI
                      _menuWideButton(
                        icon: Icons.history,
                        label: "Riwayat Absensi",
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
                      const SizedBox(height: 20),
                      const Text(
                        "KPU PROVINSI KEPRI",
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "BONDANCH@2026",
                        style: TextStyle(color: Colors.black54, fontSize: 10),
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

  // ✅ Ikon (X) tetap dihapus, ukuran Font disesuaikan
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
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
            const SizedBox(width: 4),
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
          ],
        ],
      ),
    );
  }
}

// ======================================================
// Premium Menu Button (square)
// ======================================================
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
    final Color bg = enabled ? const Color(0xFF1565C0) : Colors.grey.shade500;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 110,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
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

// ======================================================
// Premium Menu Button Wide
// ======================================================
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
    final Color bg = enabled ? const Color(0xFF1565C0) : Colors.grey.shade500;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withOpacity(0.25),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
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
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7A0C10), Color(0xFFB31217)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white),
        ],
      ),
    ),
  );
}

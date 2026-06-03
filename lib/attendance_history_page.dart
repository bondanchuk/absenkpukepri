import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final String nip;
  final String name;

  const AttendanceHistoryPage({
    super.key,
    required this.nip,
    required this.name,
  });

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  String selectedMonth = DateFormat("yyyy-MM").format(DateTime.now());

  List<String> getMonthOptions() {
    final now = DateTime.now();
    List<String> months = [];
    for (int i = 0; i < 6; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add(DateFormat("yyyy-MM").format(date));
    }
    return months;
  }

  Query<Map<String, dynamic>> getQuery() {
    final monthDate = DateTime.parse("$selectedMonth-01");
    final nextMonth = DateTime(monthDate.year, monthDate.month + 1, 1);

    final startDocId =
        "${widget.nip}_${DateFormat("yyyyMMdd").format(monthDate)}";
    final endDocId =
        "${widget.nip}_${DateFormat("yyyyMMdd").format(nextMonth)}";

    return FirebaseFirestore.instance
        .collection("attendance")
        .orderBy(FieldPath.documentId)
        .startAt([startDocId])
        .endBefore([endDocId]);
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat(
      "MMMM yyyy",
      "id_ID",
    ).format(DateTime.parse("$selectedMonth-01"));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A0C10),
        foregroundColor: Colors.white,
        title: const Text("Riwayat Absensi"),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // ==== Dropdown Bulan ====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedMonth,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  items: getMonthOptions().map((m) {
                    final label = DateFormat(
                      "MMMM yyyy",
                      "id_ID",
                    ).format(DateTime.parse("$m-01"));
                    return DropdownMenuItem(value: m, child: Text(label));
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => selectedMonth = val);
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ==== List Riwayat ====
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: getQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      "Tidak ada data absensi pada bulan $monthLabel",
                      style: const TextStyle(color: Colors.black54),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();

                    final date = data["date"] ?? "-";
                    final checkIn = data["checkInTime"];
                    final checkOut = data["checkOutTime"];
                    final statusText = data["status"] ?? ""; // Ambil status

                    // ✅ Cek apakah hari tersebut adalah hari pengajuan (izin/sakit/dinas)
                    bool isLeaveDay =
                        statusText.isNotEmpty &&
                        statusText != "Hadir" &&
                        statusText != "valid";

                    String masuk = "-";
                    String pulang = "-";

                    if (checkIn != null) {
                      masuk = DateFormat(
                        "HH:mm",
                      ).format(DateTime.parse(checkIn));
                    }
                    if (checkOut != null) {
                      pulang = DateFormat(
                        "HH:mm",
                      ).format(DateTime.parse(checkOut));
                    }

                    final sudahReport = data["reportSubmitted"] == true;

                    return Container(
                      padding: const EdgeInsets.all(14),
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
                            DateFormat(
                              "EEEE, dd MMMM yyyy",
                              "id_ID",
                            ).format(DateTime.parse(date)),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ✅ TAMPILAN BERUBAH JIKA SEDANG IZIN/DINAS
                          if (isLeaveDay)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Status: $statusText",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: _infoChip(
                                    label: "Masuk",
                                    value: masuk,
                                    icon: Icons.login,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _infoChip(
                                    label: "Pulang",
                                    value: pulang,
                                    icon: Icons.logout,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                isLeaveDay
                                    ? Icons.info
                                    : (sudahReport
                                          ? Icons.check_circle
                                          : Icons.cancel),
                                size: 18,
                                color: isLeaveDay
                                    ? Colors.orange
                                    : (sudahReport
                                          ? Colors.green
                                          : Colors.redAccent),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isLeaveDay
                                    ? "Laporan kinerja tidak diwajibkan"
                                    : (sudahReport
                                          ? "Laporan kinerja sudah diisi"
                                          : "Laporan kinerja belum diisi"),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isLeaveDay
                                      ? Colors.orange
                                      : (sudahReport
                                            ? Colors.green
                                            : Colors.redAccent),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

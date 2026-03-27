// ... imports
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../model/scan_data.dart'; 

class DataPage extends StatefulWidget {
  final List<ScanData> scanDataList;
  const DataPage({super.key, required this.scanDataList});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  List<ScanData> get limitedList => widget.scanDataList.reversed.take(100).toList();
  Set<String> get uniqueSsids => widget.scanDataList.map((data) => data.ssid).toSet();

  Future<void> _generateCsvAndOpen() async {
    if (widget.scanDataList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No data to export")),
      );
      return;
    }

    try {
      List<List<dynamic>> rows = [];
      
      // *** เพิ่ม Header IMU ***
      rows.add([
        "Index", "SSID", "BSSID", "RSSI",
        "Latitude", "Longitude", "Timestamp",
        "AccelX", "AccelY", "AccelZ", // เพิ่ม
        "GyroX", "GyroY", "GyroZ"  ,
        "MagX", "MagY", "MagZ"   // เพิ่ม
      ]);

      for (var data in widget.scanDataList) {
        rows.add([
          data.scanIndex,
          data.ssid,
          data.bssid,
          data.rssi,
          data.latitude,
          data.longitude,
          DateFormat('HH:mm:ss').format(data.timestamp),
          // *** ใส่ข้อมูล IMU ***
          data.accelX.toStringAsFixed(4),
          data.accelY.toStringAsFixed(4),
          data.accelZ.toStringAsFixed(4),
          data.gyroX.toStringAsFixed(4),
          data.gyroY.toStringAsFixed(4),
          data.gyroZ.toStringAsFixed(4),
          data.magX.toStringAsFixed(4),
          data.magY.toStringAsFixed(4),
          data.magZ.toStringAsFixed(4),
        ]);
      }

      String csvData = const ListToCsvConverter().convert(rows);

      final directory = await getApplicationDocumentsDirectory();
      final fileName = "wifi_imu_scan_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv";
      final path = "${directory.path}/$fileName";
      final file = File(path);

      await file.writeAsString(csvData);
      
      if (!mounted) return; 

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Exported $fileName successful!")),
      );

      await OpenFilex.open(path);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ... (UI ส่วน Build เหมือนเดิมทุกประการ ไม่ต้องแก้ UI ก็ได้ครับ)
  @override
  Widget build(BuildContext context) {
    // ... Copy โค้ด Build เดิมมาวางได้เลยครับ เพราะแก้แค่ฟังก์ชัน _generateCsvAndOpen
    return Scaffold(
      appBar: AppBar(
        title: const Text("Data Previews"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildStatRow("Total Data Points:", "${widget.scanDataList.length}"),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildStatRow("Unique SSIDs Found:", "${uniqueSsids.length}"),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Unique Networks Preview",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: uniqueSsids.isEmpty 
            ? const Center(child: Text("No Data"))
            : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: uniqueSsids.length,
              separatorBuilder: (ctx, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final ssid = uniqueSsids.elementAt(index);
                final count = widget.scanDataList.where((d) => d.ssid == ssid).length;
                return Container(
                  color: Colors.white,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Icon(Icons.wifi, color: Colors.blue.shade700, size: 20),
                    ),
                    title: Text(ssid, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text("Recorded $count times"), 
                    dense: true,
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _generateCsvAndOpen,
                icon: const Icon(Icons.file_download_outlined),
                label: Text("Export All (${widget.scanDataList.length}) to CSV"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color.fromARGB(255, 8, 108, 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.black54)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}
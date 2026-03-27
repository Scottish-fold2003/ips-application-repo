class ScanData {
  final int scanIndex;
  final String ssid;
  final String bssid;
  final int rssi;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  // เพิ่ม IMU Data
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double magX;
  final double magY;
  final double magZ;

  ScanData({
    required this.scanIndex,
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    // รับค่า IMU เข้ามา
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.magX,
    required this.magY,
    required this.magZ,
  });

  Map<String, dynamic> toMap() {
    return {
      'scanIndex': scanIndex,
      'ssid': ssid,
      'bssid': bssid,
      'rssi': rssi,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toString(),
      'accelX': accelX,
      'accelY': accelY,
      'accelZ': accelZ,
      'gyroX': gyroX,
      'gyroY': gyroY,
      'gyroZ': gyroZ,
      'magX': magX,
      'magY': magY,
      'magZ': magZ,
    };
  }
}
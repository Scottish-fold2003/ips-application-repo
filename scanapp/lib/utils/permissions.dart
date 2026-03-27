import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  /// ขอสิทธิ์ Location, Storage และ Manage External Storage พร้อมกัน
  static Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.storage,
      Permission.manageExternalStorage, // สำหรับ Android 11+
    ].request();

    // ตรวจสอบว่าทุก permission ผ่านหรือไม่
    return statuses.values.every((status) => status.isGranted);
  }

  /// ตรวจสอบสิทธิ์ Location
  static Future<bool> checkLocation() async {
    return await Permission.location.isGranted;
  }

  /// ตรวจสอบสิทธิ์ Storage
  static Future<bool> checkStorage() async {
    return await Permission.storage.isGranted;
  }

  /// ตรวจสอบสิทธิ์ Manage External Storage (Android 11+)
  static Future<bool> checkManageStorage() async {
    return await Permission.manageExternalStorage.isGranted;
  }
}

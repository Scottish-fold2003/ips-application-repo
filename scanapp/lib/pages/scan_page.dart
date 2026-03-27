import 'dart:async'; // อย่าลืม import นี้สำหรับ StreamSubscription
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart'; // import sensors_plus

import '../model/scan_data.dart';
import 'data_page.dart';

class ScanPage extends StatefulWidget {
  final Function(ScanData) onScanFound;
  const ScanPage({super.key, required this.onScanFound});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lottieController;
  
  // State variables
  bool _isAutoScanning = false;
  bool _isPausedScan = false;
  
  int _totalRecords = 0; 
  int _currentRound = 0; 
  
  String _scanMessage = "Ready to Scan";
  int _scanPeriod = 2; 

  // Data variables
  List<String> _ssidFilters = []; 
  List<String> _ssidHistory = []; 

  final List<ScanData> _localScanHistory = [];

  // *** IMU Variables ***
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;
  double _mx = 0, _my = 0, _mz = 0;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<MagnetometerEvent>? _magSubscription;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    loadFilters();
    _initSensors(); // เริ่มดักจับค่า Sensor
  }

  void _initSensors() {
    // ฟังค่า Accelerometer
    _accelSubscription = accelerometerEvents.listen((event) {
      if (mounted) {
        // ไม่ต้อง setState เพื่อลดการ build หน้าจอถี่เกินไป
        _ax = event.x;
        _ay = event.y;
        _az = event.z;
      }
    });

    // ฟังค่า Gyroscope
    _gyroSubscription = gyroscopeEvents.listen((event) {
      if (mounted) {
        _gx = event.x;
        _gy = event.y;
        _gz = event.z;
      }
    });

    _magSubscription = magnetometerEvents.listen((event) {
      if (mounted) {
        _mx = event.x;
        _my = event.y;
        _mz = event.z;
      }
    });
  }

  @override
  void dispose() {
    _lottieController.dispose();
    _accelSubscription?.cancel(); // ยกเลิกการฟังค่า
    _gyroSubscription?.cancel();
    _magSubscription?.cancel();
    _isAutoScanning = false; 
    super.dispose();
  }

  // ... (code _requestPermissions, loadFilters, saveFilters เหมือนเดิม) ...
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    if (statuses[Permission.location]!.isDenied) {
      if (mounted) _showSnackBar("Location permission is required.");
    }
  }

  Future<void> loadFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ssidHistory = prefs.getStringList("ssidFilters") ?? [];
      _ssidFilters = List.from(_ssidHistory);
    });
  }

  Future<void> saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("ssidFilters", _ssidHistory);
  }

  // Function View Data (คงเดิม)
  void _goToDataPage() async {
    if (_isAutoScanning && !_isPausedScan) {
      _pauseAnimation(); 
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DataPage(scanDataList: _localScanHistory),
      ),
    );
  }

  Future<void> _startAutoScan() async {
    if (_isAutoScanning) return;

    await _requestPermissions();
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
       _showSnackBar("Please Enable GPS");
    }

    setState(() {
      _isAutoScanning = true;
      _isPausedScan = false;
      if (_currentRound == 0) {
         _localScanHistory.clear();
      }
      _currentRound = 0; 
      _lottieController.repeat();
    });

    while (_isAutoScanning) {
      if (!mounted) return;

      while (_isPausedScan && _isAutoScanning) {
        if (!mounted) return;
        setState(() => _scanMessage = "Paused (Check Data...)");
        await Future.delayed(const Duration(milliseconds: 500));
      }

      setState(() {
        _currentRound++; 
        _scanMessage = "Scanning...";
      });
      
      _lottieController.stop(); 
      await Future.delayed(const Duration(milliseconds: 500)); 

      Position? pos;
      List<WifiNetwork> networks = [];

      try {
        networks = await WiFiForIoTPlugin.loadWifiList();
      } catch (e) {
        debugPrint("Scan error: $e");
      }

      try {
        if (serviceEnabled) {
          pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        }
      } catch (e) {
        pos = null;
      }

      if (!mounted) return;

      // Capture sensor data at this moment (Snapshot)
      // การเก็บแบบนี้คือเก็บค่าล่าสุด ณ วินาทีที่แสกนเสร็จ
      double curAx = _ax;
      double curAy = _ay;
      double curAz = _az;
      double curGx = _gx;
      double curGy = _gy;
      double curGz = _gz;
      double curMx = _mx; 
      double curMy = _my; 
      double curMz = _mz;

      for (var network in networks) {
        String ssid = network.ssid ?? "Unknown";
        String bssid = network.bssid ?? "N/A";
        int rssi = network.level ?? 0;

        bool acceptScan = _ssidFilters.isEmpty || _ssidFilters.contains(ssid);

        if (acceptScan) {
           _totalRecords++;

           ScanData newData = ScanData(
             scanIndex: _currentRound, 
             ssid: ssid,
             bssid: bssid,
             rssi: rssi,
             latitude: pos?.latitude ?? 0.0,
             longitude: pos?.longitude ?? 0.0,
             timestamp: DateTime.now(),
             // ใส่ค่า Sensor
             accelX: curAx,
             accelY: curAy,
             accelZ: curAz,
             gyroX: curGx,
             gyroY: curGy,
             gyroZ: curGz,
             magX: curMx, 
             magY: curMy, 
             magZ: curMz,
           );
           
           _localScanHistory.add(newData); 
           widget.onScanFound(newData);
        }
      }

      _lottieController.repeat();
      
      int countdown = _scanPeriod;
      while (countdown > 0 && _isAutoScanning && !_isPausedScan) {
        if (!mounted) return;
        setState(() {
          _scanMessage = "Walk... Next scan in ${countdown}s";
        });
        await Future.delayed(const Duration(seconds: 1));
        countdown--;
      }
    }
  }

  // ... (ส่วนที่เหลือเหมือนเดิม: _stopAutoScan, _pauseAnimation, _resumeAnimation, UI Build) ...
  void _stopAutoScan() {
    setState(() {
      _isAutoScanning = false;
      _isPausedScan = false;
      _totalRecords = 0;
      _currentRound = 0;
      _localScanHistory.clear();
      _scanMessage = "Stopped";
      _lottieController.stop();
    });
  }

  void _pauseAnimation() {
    if (!_isAutoScanning) return;
    setState(() {
      _isPausedScan = true;
      _scanMessage = "Paused";
      _lottieController.stop();
    });
  }

  void _resumeAnimation() {
    if (!_isAutoScanning) return;
    setState(() {
      _isPausedScan = false;
      _lottieController.repeat();
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)),
    );
  }

  void _showFilterDialog() async {
    final TextEditingController controller = TextEditingController();
    List<String> tempSelected = List.from(_ssidFilters);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("SSID Filter"),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: "Add New SSID", suffixIcon: Icon(Icons.wifi)),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: tempSelected.length == _ssidHistory.length && _ssidHistory.isNotEmpty,
                      title: const Text("Select All"),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        setStateDialog(() {
                          if (value == true) tempSelected = List.from(_ssidHistory);
                          else tempSelected.clear();
                        });
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: _ssidHistory.isEmpty 
                        ? const Center(child: Text("No saved SSIDs"))
                        : ListView(
                          children: _ssidHistory.map((ssid) => CheckboxListTile(
                            value: tempSelected.contains(ssid),
                            title: Text(ssid),
                            onChanged: (value) {
                              setStateDialog(() {
                                if (value == true) tempSelected.add(ssid);
                                else tempSelected.remove(ssid);
                              });
                            },
                          )).toList(),
                        ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    if (controller.text.isNotEmpty && !_ssidHistory.contains(controller.text)) {
                      _ssidHistory.add(controller.text);
                      tempSelected.add(controller.text); 
                      await saveFilters();
                    }
                    if (mounted) setState(() => _ssidFilters = tempSelected);
                    Navigator.pop(context);
                  },
                  child: const Text("Save & Apply"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0, left: 16, right: 16),
      child: Column(
        children: <Widget>[
          const Spacer(),
          // Top Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _goToDataPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade800,
                ),
                icon: const Icon(Icons.bar_chart),
                label: Text("View Data (${_localScanHistory.length})"),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _showFilterDialog,
                icon: const Icon(Icons.filter_list),
                label: const Text("Filter"),
              ),
            ],
          ),
          
          const Spacer(),
          
          Lottie.asset(
            'assets/animations/walk_animation.json',
            controller: _lottieController,
            width: 200,
            height: 200,
            onLoaded: (comp) => _lottieController.duration = comp.duration,
            errorBuilder: (ctx, err, stack) => const Icon(Icons.directions_walk, size: 100, color: Colors.grey),
          ),
          
          const SizedBox(height: 20),
          
          Text(
            _scanMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          
          Text(
            _currentRound == 0 
                ? "Waiting to start..." 
                : "Scan Round: #$_currentRound  (Records: $_totalRecords)",
            style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w500),
          ),
          
          // (Optional) Display Real-time Sensor values for debug
          // Text("Ax:${_ax.toStringAsFixed(2)} Ay:${_ay.toStringAsFixed(2)} Az:${_az.toStringAsFixed(2)}", style: const TextStyle(fontSize: 10, color: Colors.grey)),

          const Spacer(),

          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Walk Interval: ", style: TextStyle(fontWeight: FontWeight.w600)),
                  DropdownButton<int>(
                    value: _scanPeriod,
                    items: [2, 3, 5, 10].map((e) => DropdownMenuItem(value: e, child: Text("$e s"))).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _scanPeriod = value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAutoScanning ? Colors.grey : Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isAutoScanning ? null : _startAutoScan,
                  child: const Text("START SCAN", style: TextStyle(fontSize: 18)),
                ),
              ),
              
              const SizedBox(height: 20),
              
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isAutoScanning ? _stopAutoScan : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
                      child: const Text("Stop", style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isAutoScanning && !_isPausedScan) ? _pauseAnimation : null,
                      child: const Text("Pause"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isAutoScanning && _isPausedScan) ? _resumeAnimation : null,
                      child: const Text("Resume"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
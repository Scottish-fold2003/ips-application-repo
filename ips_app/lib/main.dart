import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ips_engine.dart';
import 'mock_data.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CMKL Indoor Nav',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ==========================================
// SplashScreen สำหรับหน้าโหลดรูป 3 วินาที
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MyHomePage(title: 'CMKL Navigation'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/splash_logo.jpg',
          width: 1200,
          height: 1200,
          fit: BoxFit.fill,
        ),
      ),
    );
  }
}

// ==========================================
// MyHomePage
// ==========================================
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();

  late AnimationController _cameraAnimationController;
  Animation<Matrix4>? _cameraAnimation;

  String selectedBuilding = "CMKL";
  String selectedFloor = "6th";
  bool _showPin = false;
  String _currentStatus = "Waiting for start...";

  double _rawX = 0.0;
  double _rawY = 0.0;

  bool _isFirstLocation = true;
  bool _isTracking = false;

  double _smoothedX = 0.0;
  double _smoothedY = 0.0;

  int _wifiCount = 0;

  final IPSModel _ips = IPSModel();
  Timer? _timer;
  double _pinX = 0;
  double _pinY = 0;
  bool _isScanning = false;

  bool _isSimulationMode = false;
  bool _isRedMode = false;

  bool _showTopNotification = false;
  String _topNotificationText = "";
  Timer? _notificationTimer;

  // ==========================================
  // 🐛 DEBUG LOG PANEL
  // ==========================================
  bool _showDebugPanel = false;
  final List<String> _debugLogs = [];

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _debugLogs.insert(0, "[${DateTime.now().second}s] $msg");
      if (_debugLogs.length > 20) _debugLogs.removeLast();
    });
  }
  // ==========================================

  final Map<String, Map<String, double>> floorConfigs = {
    "6th": {"pixelsPerMeter": 50.0, "offsetX": 590.0, "offsetY": 2230.0},
    "7th": {"pixelsPerMeter": 50.0, "offsetX": 680.0, "offsetY": 2380.0},
  };

  void _showFloorChangeSnackBar(String floor) {
    _notificationTimer?.cancel();

    if (mounted) {
      setState(() {
        _topNotificationText = 'Floor changed to $floor';
        _showTopNotification = true;
      });

      _notificationTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showTopNotification = false;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initIPS();

    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        if (_cameraAnimation != null) {
          _transformationController.value = _cameraAnimation!.value;
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transformationController.value = Matrix4.identity()..scale(0.15);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notificationTimer?.cancel();
    _cameraAnimationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _initIPS() async {
    try {
      final String jsonContent = await rootBundle.loadString(
        'assets/json/ips_model.json',
      );
      final Map<String, dynamic> data = json.decode(jsonContent);
      await _ips.loadModel(data);
      await Permission.location.request();

      _addLog("✅ Model loaded: ${_ips.database.length} points");

      _timer = Timer.periodic(
        const Duration(milliseconds: 3000),
        (timer) => _scanAndPredict(),
      );

      if (mounted) setState(() => _currentStatus = "Model Loaded Successfully");
    } catch (e) {
      debugPrint("❌ JSON Error: $e");
      _addLog("❌ JSON Error: $e");
      if (mounted) {
        setState(() => _currentStatus = "Error: JSON Path not found");
      }
    }
  }

  Map<String, double> _applySmoothMovement(double rawX, double rawY) {
    if (_isFirstLocation || (_smoothedX == 0.0 && _smoothedY == 0.0)) {
      _smoothedX = rawX;
      _smoothedY = rawY;
      _isFirstLocation = false;
      return {'x': _smoothedX, 'y': _smoothedY};
    }

    double distance = sqrt(
      pow(rawX - _smoothedX, 2) + pow(rawY - _smoothedY, 2),
    );

    double alpha;
    if (distance < 1.0) {
      alpha = 0.5;
    } else if (distance < 3.0) {
      alpha = 0.8;
    } else {
      alpha = 1.0;
    }

    _smoothedX = _smoothedX + alpha * (rawX - _smoothedX);
    _smoothedY = _smoothedY + alpha * (rawY - _smoothedY);

    return {'x': _smoothedX, 'y': _smoothedY};
  }

  Future<void> _scanAndPredict() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      Map<String, int> inputs = {};

      if (_isSimulationMode) {
        await Future.delayed(const Duration(milliseconds: 100));
        MockScenario mock = MockData.getNextScenario();
        inputs = mock.signals;
      } else {
        final canScan = await WiFiScan.instance.canStartScan(
          askPermissions: true,
        );
        if (canScan == CanStartScan.yes) {
          await WiFiScan.instance.startScan();
        }

        final results = await WiFiScan.instance.getScannedResults();
        for (var res in results) {
          String ssid = res.ssid;
          if (ssid == "CMKL" || ssid == "CMKL-IoT" || ssid == "CMKL-Guest") {
            inputs[res.bssid.toLowerCase()] = res.level;
          }
        }
      }

      // 🐛 LOG: จำนวน MAC ที่ scan เจอ
      _addLog("📶 MACs found: ${inputs.length}");
      if (inputs.isNotEmpty) {
        _addLog("📶 MACs: ${inputs.keys.map((k) => k.substring(k.length - 5)).join(', ')}");
      }

      if (mounted) {
        setState(() {
          _wifiCount = inputs.length;
        });
      }

      if (inputs.isNotEmpty) {
        final String jsonPayload = jsonEncode(inputs);
        final int bytesSize = utf8.encode(jsonPayload).length;
        _addLog("📡 Payload: $bytesSize bytes");
        debugPrint('📡 [Network Overhead] Simulated Payload per scan: $bytesSize bytes');

        final stopwatch = Stopwatch()..start();
        var result = _ips.predict(inputs);
        stopwatch.stop();
        
        _addLog("⏱️ Latency: ${stopwatch.elapsedMilliseconds} ms");

        debugPrint('⏱️ [Latency] Prediction Execution Time: ${stopwatch.elapsedMilliseconds} ms (${stopwatch.elapsedMicroseconds} microseconds)');

        _addLog("🧠 status: ${result['status']}");

        if (result['status'] == 'success') {
          _addLog("📍 x:${(result['x'] as num).toStringAsFixed(2)} y:${(result['y'] as num).toStringAsFixed(2)} floor:${result['floor']}");
        }

        if (result['status'] == 'success') {
          if (mounted) {
            setState(() {
              double rawResultX = (result['x'] as num).toDouble();
              double rawResultY = (result['y'] as num).toDouble();
              int rawFloor = result['floor'] as int;
              String predictedFloorText = rawFloor == 0 ? "6th" : "7th";

              if (selectedFloor != predictedFloorText) {
                selectedFloor = predictedFloorText;
                _isFirstLocation = true;
                _smoothedX = 0.0;
                _smoothedY = 0.0;

                _showFloorChangeSnackBar(selectedFloor);
              }

              var smoothedCoords = _applySmoothMovement(rawResultX, rawResultY);
              _rawX = smoothedCoords['x']!;
              _rawY = smoothedCoords['y']!;

              final config =
                  floorConfigs[selectedFloor] ?? floorConfigs["6th"]!;
              _pinX = config["offsetX"]! + (_rawX * config["pixelsPerMeter"]!);
              _pinY = config["offsetY"]! - (_rawY * config["pixelsPerMeter"]!);

              _showPin = true;
              _currentStatus = "🎯 CMKL Online : $selectedFloor Floor";

              if (_isTracking) {
                _centerCameraOnPin(animate: true);
              }
            });
          }
        } else if (result['status'] == 'out_of_service') {
          if (mounted) {
            setState(() {
              _showPin = false;
              _currentStatus = "⚠️ Out of Service Area (No Match)";
            });
          }
        }
      } else {
        // 🐛 LOG: ไม่เจอ WiFi เลย
        _addLog("❌ No CMKL WiFi found");
        if (mounted) {
          setState(() {
            _showPin = false;
            if (!_isSimulationMode) {
              _currentStatus = "🔍 Searching for CMKL WiFi...";
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      _addLog("❌ Error: $e");
    } finally {
      _isScanning = false;
    }
  }

  String _getMapAsset() {
    return selectedFloor == "7th"
        ? 'assets/images/map7_floor.png'
        : 'assets/images/map6_floor.png';
  }

  void _toggleTracking() {
    setState(() {
      _isTracking = !_isTracking;
    });
    if (_isTracking && _showPin) {
      _centerCameraOnPin(animate: true);
    } else {
      _cameraAnimationController.stop();
    }
  }

  void _centerCameraOnPin({bool animate = true}) {
    const double zoomLevel = 0.4;
    final Size screenSize = MediaQuery.of(context).size;
    final double x = -(_pinX * zoomLevel) + (screenSize.width / 2);
    final double y = -(_pinY * zoomLevel) + (screenSize.height / 2);

    final Matrix4 endMatrix = Matrix4.identity()
      ..translate(x, y)
      ..scale(zoomLevel);

    if (animate) {
      _cameraAnimation = Matrix4Tween(
        begin: _transformationController.value,
        end: endMatrix,
      ).animate(
        CurvedAnimation(
          parent: _cameraAnimationController,
          curve: Curves.easeInOut,
        ),
      );
      _cameraAnimationController.forward(from: 0.0);
    } else {
      _transformationController.value = endMatrix;
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = floorConfigs[selectedFloor] ?? floorConfigs["6th"]!;

    int targetFloorLevel = selectedFloor == "7th" ? 1 : 0;
    List<Map<String, dynamic>> currentFloorPoints =
        _ips.database.where((point) {
      return point['floor'] == targetFloorLevel;
    }).toList();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformationController,
            onInteractionStart: (details) {
              if (_isTracking) {
                setState(() {
                  _isTracking = false;
                });
                _cameraAnimationController.stop();
              }
            },
            minScale: 0.01,
            maxScale: 10.0,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(5000),
            child: Stack(
              children: [
                Image.asset(_getMapAsset(), fit: BoxFit.contain),
                Positioned.fill(
                  child: CustomPaint(
                    painter: MapPainter(
                      x: _rawX,
                      y: _rawY,
                      allPoints: currentFloorPoints,
                      scale: config["pixelsPerMeter"]!,
                      offX: config["offsetX"]!,
                      offY: config["offsetY"]!,
                      showDebug: _isRedMode,
                    ),
                  ),
                ),
                if (_showPin)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOut,
                    left: _pinX - 250,
                    top: _pinY - 250,
                    child: _buildLocationPin(),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Column(
              children: [
                _buildControlCard(),
                const SizedBox(height: 12),
                _buildStatusPill(),
              ],
            ),
          ),
          // ==========================================
          // 🐛 DEBUG PANEL (ด้านล่างของหน้าจอ)
          // ==========================================
          if (_showDebugPanel)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              height: 200,
              child: Container(
                color: Colors.black.withOpacity(0.85),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "🐛 DEBUG LOG",
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _debugLogs.clear()),
                          child: const Text(
                            "CLEAR",
                            style: TextStyle(color: Colors.orange, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _debugLogs.length,
                        itemBuilder: (ctx, i) => Text(
                          _debugLogs[i],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // ==========================================
          // 🐛 DEBUG TOGGLE BUTTON (มุมซ้ายล่าง)
          // ==========================================
          Positioned(
            bottom: 16,
            left: 16,
            child: GestureDetector(
              onTap: () => setState(() => _showDebugPanel = !_showDebugPanel),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _showDebugPanel ? Colors.greenAccent : Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _showDebugPanel ? "🐛 Hide Log" : "🐛 Show Log",
                  style: TextStyle(
                    color: _showDebugPanel ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // ==========================================
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            top: _showTopNotification ? 180.0 : -100.0,
            left: 20,
            right: 20,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 247, 234, 0),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.elevator,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _topNotificationText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 0, 0, 0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _isTracking ? Colors.blue : Colors.orange,
        onPressed: _toggleTracking,
        shape: const CircleBorder(),
        child: Icon(
          _isTracking ? Icons.my_location : Icons.location_searching,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildControlCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.home_work, color: Colors.orange),
              const SizedBox(width: 10),
              Text(
                selectedBuilding,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: selectedFloor,
                onChanged: (v) {
                  if (v != null && v != selectedFloor) {
                    setState(() {
                      selectedFloor = v;
                      _showPin = false;
                      _isFirstLocation = true;
                      _smoothedX = 0.0;
                      _smoothedY = 0.0;
                      _isTracking = false;
                      _cameraAnimationController.stop();
                    });
                    _showFloorChangeSnackBar(selectedFloor);
                  }
                },
                items: ['6th', '7th']
                    .map(
                      (val) => DropdownMenuItem(value: val, child: Text(val)),
                    )
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill() {
    bool isOk = _currentStatus.contains("Online") ||
        _currentStatus.contains("📍") ||
        _currentStatus.contains("🎯") ||
        _currentStatus.contains("Loaded");

    if (_currentStatus.contains("⚠️")) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _currentStatus,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isOk ? Colors.green : Colors.orange,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _currentStatus,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLocationPin() {
    return SizedBox(
      width: 500,
      height: 500,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withOpacity(0.2),
            ),
          ),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(color: Colors.white, width: 5),
            ),
          ),
        ],
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  final double x, y, scale, offX, offY;
  final List<Map<String, dynamic>> allPoints;
  final bool showDebug;

  MapPainter({
    required this.x,
    required this.y,
    required this.allPoints,
    required this.scale,
    required this.offX,
    required this.offY,
    required this.showDebug,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showDebug) {
      if (allPoints.isNotEmpty) {
        final paintDb = Paint()
          ..color = Colors.black.withOpacity(0.4)
          ..style = PaintingStyle.fill;
        for (var point in allPoints) {
          double px = offX + (point['x']! * scale);
          double py = offY - (point['y']! * scale);
          canvas.drawCircle(Offset(px, py), 5.0, paintDb);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
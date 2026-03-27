import 'dart:math';
import 'package:flutter/foundation.dart';

class IPSModel {
  List<Map<String, dynamic>> database = [];
  List<String> dbHeaders = [];
  bool isLoaded = false;

  // 🔥 ตั้งค่าตัวแปรใหม่ตามที่กำหนด
  final double NO_SIGNAL = 100.0;
  final double REPLACE_RSSI = -95.0;
  final int MIN_CLUSTER_SIZE = 2;
  final double EPS = 1e-6;

  final int K_FLOOR = 3;
  final int K_POS = 15;
  final double RADIUS = 80.0;
  final double CONF = 0.85;

  // 🎯 ใช้ List นี้เป็นตัวตั้งต้นในการเช็ค (ต้องเรียงตรงกับ rssi_list ใน JSON)
  final List<String> orderedMacs = [
    "68:3a:1e:2e:c5:17",
    "68:3a:1e:2e:c5:1a",
    "68:3a:1e:2e:c5:20",
    "68:3a:1e:2e:c5:01",
    "68:3a:1e:2e:c1:17",
    "68:3a:1e:2e:c5:05",
    "68:3a:1e:2e:c5:33",
    "2c:3f:0b:56:e8:fb",
    "2c:3f:0b:56:e8:f1",
    "2c:3f:0b:56:e9:00",
    "2c:3f:0b:56:e9:15",
    "2c:3f:0b:56:e8:f7",
    "2c:3f:0b:56:e9:2a",
    "2c:3f:0b:56:e6:18",
    "2c:3f:0b:56:e9:03",
    "2c:3f:0b:57:fa:37",
    "2c:3f:0b:56:e9:0d",
    "e4:55:a8:26:73:ef",
  ];

  Future<void> loadModel(Map<String, dynamic> jsonSource) async {
    try {
      dbHeaders = (jsonSource["mac_addresses"] as List)
          .sublist(1)
          .map((e) => e.toString().toLowerCase())
          .toList();

      database = (jsonSource["database"] as List).map((item) {
        return {
          "x": (item["x"] as num).toDouble(),
          "y": (item["y"] as num).toDouble(),
          "floor": item["floor"],
          "rssi_list": (item["rssi"] as List).sublist(1),
        };
      }).toList();

      isLoaded = true;
      debugPrint(
        "✅ Model Loaded: Ready to match with ${orderedMacs.length} MACs",
      );
    } catch (e) {
      debugPrint("❌ Load Model Error: $e");
    }
  }

  Map<String, dynamic> predict(Map<String, int> scanResult, {int? forceFloor}) {
    if (!isLoaded || database.isEmpty) return {"status": "loading"};

    Map<String, int> cleanScan = {};
    scanResult.forEach((key, value) => cleanScan[key.toLowerCase()] = value);

    List<Map<String, dynamic>> calculatedDistances = [];
    bool foundAnyMatchInDb = false;
    int maxMatchFound = 0;

    for (var point in database) {
      double sumSquareDiff = 0;
      int matchCount = 0;
      List<dynamic> dbRssiList = point["rssi_list"];

      for (int i = 0; i < orderedMacs.length; i++) {
        if (i >= dbRssiList.length) break;

        String targetMac = orderedMacs[i];

        // 1. จัดการค่าสัญญาณใน DB (ถ้าใน DB เป็นค่าว่าง/ไม่มีสัญญาณ ให้แปลงเป็น REPLACE_RSSI)
        double dbRssi = (dbRssiList[i] as num).toDouble();
        if (dbRssi == NO_SIGNAL) {
          dbRssi = REPLACE_RSSI;
        }

        // 2. จัดการค่าสัญญาณจากการสแกน (ถ้าไม่เจอให้ใช้ REPLACE_RSSI)
        double currentRssi;
        if (cleanScan.containsKey(targetMac)) {
          currentRssi = cleanScan[targetMac]!.toDouble();
          matchCount++;
        } else {
          currentRssi = REPLACE_RSSI;
        }

        sumSquareDiff += pow(currentRssi - dbRssi, 2);
      }

      if (matchCount > maxMatchFound) {
        maxMatchFound = matchCount;
      }

      if (matchCount == 0) continue;

      double distance = sqrt(sumSquareDiff);

      // 3. กรองด้วย RADIUS: ถ้าระยะห่างในมิติสัญญาณมากกว่า RADIUS (80) ถือว่าจุดนี้ไม่ใช่ candidate แน่นอน
      if (distance <= RADIUS) {
        foundAnyMatchInDb = true;
        calculatedDistances.add({"point": point, "distance": distance});
      }
    }

    if (!foundAnyMatchInDb || calculatedDistances.isEmpty) {
      debugPrint(
        "⚠️ No Match! Signal distances exceeded RADIUS ($RADIUS) or no MACs matched.",
      );
      return {"status": "out_of_service"};
    }

    // เรียงจุดที่ใกล้ที่สุด (ค่าน้อยสุดแปลว่าใกล้สุด)
    calculatedDistances.sort((a, b) => a["distance"].compareTo(b["distance"]));

    int predictedFloor;

    // 4. การทำนายชั้น (Floor Prediction) โดยใช้ K_FLOOR, CONF และ MIN_CLUSTER_SIZE
    if (forceFloor != null) {
      predictedFloor = forceFloor;
    } else {
      int actualKFloor = min(K_FLOOR, calculatedDistances.length);
      Map<int, int> floorVotes = {};

      for (int i = 0; i < actualKFloor; i++) {
        int f = calculatedDistances[i]["point"]["floor"];
        floorVotes[f] = (floorVotes[f] ?? 0) + 1;
      }

      var bestVote = floorVotes.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      double confidence = bestVote.value / actualKFloor;

      // ตรวจสอบความน่าเชื่อถือ: โหวตต้องถึงขั้นต่ำ และค่าความมั่นใจต้อง >= CONF (0.85)
      if (bestVote.value < MIN_CLUSTER_SIZE || confidence < CONF) {
        debugPrint(
          "⚠️ Floor Prediction Failed: Confidence ($confidence) < $CONF OR Votes (${bestVote.value}) < $MIN_CLUSTER_SIZE",
        );
        return {"status": "out_of_service"};
      }

      predictedFloor = bestVote.key;
    }

    var pointsInPredictedFloor = calculatedDistances
        .where((d) => d["point"]["floor"] == predictedFloor)
        .toList();

    // 5. การคำนวณพิกัด (Positioning) ต้องมีจุดอ้างอิงอย่างน้อยตาม MIN_CLUSTER_SIZE
    if (pointsInPredictedFloor.length < MIN_CLUSTER_SIZE) {
      return {"status": "out_of_service"};
    }

    int actualKPos = min(K_POS, pointsInPredictedFloor.length);
    var topK = pointsInPredictedFloor.take(actualKPos).toList();

    double sumWeights = 0;
    double sumX = 0;
    double sumY = 0;

    for (var item in topK) {
      // 6. ใช้ EPSILON (1e-6) ป้องกันการหารด้วยศูนย์ กรณีสัญญาณตรงเป๊ะ 100%
      double weight = 1.0 / (item["distance"] + EPS);
      sumWeights += weight;
      sumX += item["point"]["x"] * weight;
      sumY += item["point"]["y"] * weight;
    }

    return {
      "status": "success",
      "x": sumX / sumWeights,
      "y": sumY / sumWeights,
      "floor": predictedFloor,
    };
  }
}

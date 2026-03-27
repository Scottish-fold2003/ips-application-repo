class MockScenario {
  final String name;
  final int floorId;
  final Map<String, int> signals;

  MockScenario(this.name, this.floorId, this.signals);
}

class MockData {
  static int _currentIndex = 0;

  static final List<MockScenario> scenarios = [
    // จุดที่ 1: เจอพิกัดปกติ
    MockScenario("Zone A (Near 17)", 0, {
      "68:3a:1e:2e:c5:17": -35,
      "68:3a:1e:2e:c5:1a": -80,
    }),
    
    // จุดที่ 2: เจอพิกัดปกติ
    MockScenario("Zone B (Near 0D)", 0, {
      "2c:3f:0b:56:e9:0d": -40,
      "2c:3f:0b:56:e8:fb": -75,
    }),

    // จุดที่ 3: เจอพิกัดปกติ
    MockScenario("Zone C (Near EF)", 0, {
      "e4:55:a8:26:73:ef": -30,
      "2c:3f:0b:57:fa:37": -70,
    }),

    // 🔴 จุดที่ 4: เพิ่มกรณีเดินออกนอกพื้นที่ (Out of Service)
    MockScenario("Out of Service Zone", 0, {
      "ff:ff:ff:ff:ff:ff": -85, // ใส่ MAC Address มั่วๆ ที่ไม่มีในระบบ
      "aa:bb:cc:dd:ee:ff": -90, // สัญญาณอ่อนๆ 
    }),
  ];

  static MockScenario getNextScenario() {
    final scenario = scenarios[_currentIndex];
    print(
      "🛠️ SIMULATION: Testing [${scenario.name}] with MACs: ${scenario.signals.keys.toList()}",
    );
    
    // วนลูปไปเรื่อยๆ ตามลำดับ (A -> B -> C -> Out of Service -> กลับไป A ใหม่)
    _currentIndex = (_currentIndex + 1) % scenarios.length;
    return scenario;
  }
}
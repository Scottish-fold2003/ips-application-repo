import 'package:flutter/material.dart';
import 'package:scanapp/components/bottom_nav_bar.dart';
import 'package:scanapp/pages/data_page.dart';
import 'package:scanapp/pages/scan_page.dart';
import '../model/scan_data.dart'; // 1. อย่าลืม import model

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // 2. สร้างตัวแปรกลางสำหรับเก็บข้อมูลไว้ที่นี่ (Parent State)
  List<ScanData> _globalScanData = [];

  // 3. สร้างฟังก์ชันเพื่อรับค่าจาก ScanPage มาเติมใน List
  void _onScanFound(ScanData newData) {
    setState(() {
      _globalScanData.add(newData);
    });
  }

  void navigateBottomBar(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 4. แก้ไข List _pages ให้ส่งข้อมูลหากันได้
    final List<Widget> pages = [
      // หน้า Scan: ส่งฟังก์ชัน _onScanFound เข้าไป เพื่อให้มันส่งข้อมูลกลับมา
      ScanPage(onScanFound: _onScanFound),
      // หน้า Data: ส่ง List _globalScanData เข้าไป (แก้ Error ตรงนี้!!)
      DataPage(scanDataList: _globalScanData),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: MyBottomNavBar(
        onTabChange: (index) => navigateBottomBar(index),
      ),
      body: pages[_selectedIndex], // เรียกใช้ตัวแปร pages ที่เราสร้างใน build
    );
  }
}

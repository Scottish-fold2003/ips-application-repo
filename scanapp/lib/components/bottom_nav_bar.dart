import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

class MyBottomNavBar extends StatelessWidget {
  final ValueChanged<int> onTabChange;
  MyBottomNavBar({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(25),
      child: GNav(
        onTabChange: (value) => onTabChange(value),
        color: Colors.grey[400]!,
        mainAxisAlignment: MainAxisAlignment.center,
        activeColor: Colors.white,
        tabBackgroundColor: const Color.fromARGB(255, 0, 45, 168),
        tabBorderRadius: 20,
        tabActiveBorder: Border.all(color: const Color.fromARGB(255, 255, 255, 255)),
        tabs: [
          GButton(icon: Icons.wifi, text: ' Scan' , textStyle: TextStyle(fontWeight: FontWeight.bold , fontSize: 18, color: Colors.white),),
          GButton(icon: Icons.storage, text: ' Data', textStyle: TextStyle(fontWeight: FontWeight.bold , fontSize: 18, color: Colors.white),),
        ],
      ),
    );
  }
}

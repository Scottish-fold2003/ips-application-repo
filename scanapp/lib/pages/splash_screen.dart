import 'package:flutter/material.dart';
import 'package:scanapp/pages/home_page.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> 
  with SingleTickerProviderStateMixin {
  
  static const Color _backgroundColor = Colors.white;
  static const Color _primaryColor = Color.fromARGB(255, 0, 45, 168);
  late final AnimationController _lottieController;

  @override
    void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Lottie.asset(
              'assets/animations/wifi_animation.json',
              width: 200,
              height: 200,
              onLoaded: (composition) {
                _lottieController
                  ..duration = composition.duration
                  ..repeat();
              }
            ),
            SizedBox(height: size.height * 0.08,),
            Text(
              "Survey Networks",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
            Text(
              "Let's check your signal strength!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF555555)
              ),
            ),
            SizedBox(height: size.height * 0.08,),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  _lottieController.stop();
                  await Future.delayed(Duration(milliseconds: 50));
                  Navigator.pushReplacement(
                    context, 
                    PageRouteBuilder(
                      transitionDuration: Duration(milliseconds: 50),
                      pageBuilder: (context, animation, secondaryAnimation) =>
                        HomePage(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      }
                    )
                  );
                }, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Ready to scan?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
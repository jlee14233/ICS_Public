import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/glider_provider.dart';
import 'providers/alarm_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GliderProvider()),
        ChangeNotifierProvider(create: (_) => AlarmProvider()),
      ],
      child: const GliderDashboardApp(),
    ),
  );
}

class GliderDashboardApp extends StatelessWidget {
  const GliderDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glider Control Room',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const DashboardScreen(),
    );
  }
}

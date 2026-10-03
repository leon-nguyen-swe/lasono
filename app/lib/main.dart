import 'package:flutter/material.dart';

void main() {
  runApp(const LasonoApp());
}

class LasonoApp extends StatelessWidget {
  const LasonoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaSono',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Scaffold(body: Center(child: Text('LaSono'))),
    );
  }
}

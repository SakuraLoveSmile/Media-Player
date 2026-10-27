import 'package:flutter/material.dart';

void main() {
  runApp(const MediaPlayerApp());
}

class MediaPlayerApp extends StatelessWidget {
  const MediaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Media Player',
      home: Scaffold(
        body: Center(child: Text('Media Player')),
      ),
    );
  }
}

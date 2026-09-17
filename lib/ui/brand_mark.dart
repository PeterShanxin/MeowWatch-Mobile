import 'package:flutter/material.dart';

class MeowWatchMark extends StatelessWidget {
  const MeowWatchMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.23),
    child: Image.asset(
      'assets/brand/meowwatch-256.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'MeowWatch',
    ),
  );
}

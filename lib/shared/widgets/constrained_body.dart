import 'package:flutter/material.dart';

/// A pass-through wrapper kept for compatibility at call sites.
/// Desktop content now expands with the available window width.
class ConstrainedBody extends StatelessWidget {
  const ConstrainedBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

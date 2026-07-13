import 'package:flutter/material.dart';

/// Provides one focus traversal group and announces the application landmark.
/// MediaQuery is preserved so OS text scaling and reduced-motion preferences
/// continue to flow to every feature.
class AccessibleApp extends StatelessWidget {
  const AccessibleApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Semantics(
        container: true,
        label: 'Agriculture Pest and Disease Detection System',
        child: child,
      ),
    );
  }
}

extension ReducedMotionContext on BuildContext {
  bool get reduceMotion {
    final media = MediaQuery.maybeOf(this);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  Duration motionDuration(Duration preferred) =>
      reduceMotion ? Duration.zero : preferred;
}

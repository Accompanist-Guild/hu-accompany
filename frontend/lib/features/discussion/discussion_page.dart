import 'package:flutter/material.dart';

import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Placeholder for the Discussion Hub, which isn't built yet.
class DiscussionPage extends StatelessWidget {
  const DiscussionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: PracticePalette.ivory,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forum_rounded,
                  size: 48,
                  color: PracticePalette.lightGold,
                ),
                SizedBox(height: Space.md),
                Text(
                  'Discussion Hub',
                  style: TextStyle(
                    color: PracticePalette.brown,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: Space.xs),
                Text(
                  'Coming soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PracticePalette.mutedBrown,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/features/search/Music_Library_Page.dart';

import 'support/auth_fakes.dart';

/// The score library is a selection from PDMX, licensed CC BY 4.0, which asks for credit, a licence notice and a
/// link. The Terms of Service page has all three, so the credit line at the foot of the browse list links there.
void main() {
  testWidgets('the PDMX credit is readable and opens the Terms of Service', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final links = FakeLinkOpener();

    await tester.pumpWidget(MaterialApp(home: Music_Library_Page(links: links)));
    await tester.pump();

    final credit = find.byKey(const ValueKey('pdmx-credit'));
    expect(credit, findsOneWidget);
    expect(find.textContaining('PDMX'), findsOneWidget);
    expect(find.textContaining('CC BY 4.0'), findsOneWidget);

    await tester.ensureVisible(credit);
    await tester.tap(credit);
    await tester.pump();

    expect(links.opened, [AppConstants.termsOfServiceUrl]);
  });
}

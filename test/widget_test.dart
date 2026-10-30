// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thiak_thiak_mobile/main.dart';

void main() {
  testWidgets('Le téléphone Galaxy fictif se manipule sur petit écran', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ThiakThiakApp());
    await tester.pump();

    expect(find.text('THIAK-THIAK'), findsOneWidget);
    expect(find.text('Commander une moto'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Aperçu sur un Galaxy fictif'));
    await tester.pumpAndSettle();

    expect(find.text('Aperçu Samsung Galaxy'), findsOneWidget);
    expect(find.text('Où souhaitez-vous aller ?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Compte'));
    await tester.pumpAndSettle();
    expect(find.text('Compte de démonstration'), findsOneWidget);
    await tester.tap(find.text('Accueil').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Commander une moto').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commander une moto').last);
    await tester.pumpAndSettle();

    expect(find.text('Simulation de démonstration'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Dakar');
    await tester.enterText(find.byType(TextField).at(1), 'Plateau');
    await tester.tap(find.text('Confirmer la commande'));
    await tester.pumpAndSettle();

    expect(find.text('Commande simulée !'), findsOneWidget);
    await tester.tap(find.text('Retour à l’accueil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Courses'));
    await tester.pumpAndSettle();

    expect(find.text('Dakar → Plateau'), findsOneWidget);
    await tester.tap(find.text('Accueil').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Devenir motard'));
    await tester.tap(find.text('Devenir motard'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Awa Ndiaye');
    await tester.enterText(find.byType(TextField).at(1), '770000000');
    await tester.tap(find.text('Envoyer ma demande'));
    await tester.pumpAndSettle();

    expect(find.text('Demande simulée !'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

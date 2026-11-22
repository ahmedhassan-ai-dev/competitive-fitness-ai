import 'package:competitive_fitness_mobile/shared/fitarena_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in <double>[320, 360]) {
    for (final textScale in <double>[1, 2]) {
      testWidgets('FitArena header fits $width px at text scale $textScale',
          (tester) async {
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(
          tester.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              centerTitle: true,
              leading: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.arrow_back),
              ),
              title: const FitArenaBrandHeader(),
              actions: <Widget>[
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.person),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
          ),
        ));
        expect(find.text('FitArena'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

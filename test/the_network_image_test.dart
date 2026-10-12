import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/shared_widget/the_network_image.dart';

void main() {
  Future<CachedNetworkImage> pumpImage(
      WidgetTester tester, double parentWidth, TheNetworkImage image) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1600); // 400x800 logical
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: parentWidth, child: image),
      ),
    ));
    final widget =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    while (tester.takeException() != null) {} // no real network in tests
    return widget;
  }

  testWidgets('RES-105: feed card image decodes at displayed width',
      (tester) async {
    final image = await pumpImage(
        tester,
        360,
        const TheNetworkImage(
            url: 'https://example.com/a.jpg',
            height: 160,
            width: double.infinity));
    expect(image.memCacheWidth, 720); // 360dp * 2
    expect(image.memCacheHeight, isNull);
  });

  testWidgets('RES-105: square thumbnail decodes by height to fill the box',
      (tester) async {
    final image = await pumpImage(
        tester,
        400,
        const TheNetworkImage(
            url: 'https://example.com/a.jpg', width: 64, height: 64));
    expect(image.memCacheWidth, isNull);
    expect(image.memCacheHeight, 128);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/service/analytics_batcher.dart';

Map<String, dynamic> event(int n) => {'name': 'e$n'};

List<String> names(List<Map<String, dynamic>> batch) =>
    [for (final e in batch) e['name'] as String];

void main() {
  // testWidgets for its fake clock: tester.pump advances timers.
  testWidgets('sends a batch as soon as 10 events are queued', (tester) async {
    final sent = <List<Map<String, dynamic>>>[];
    final batcher = AnalyticsBatcher(send: (b) async => sent.add(b));

    for (var i = 0; i < 9; i++) {
      batcher.add(event(i));
    }
    expect(sent, isEmpty);
    batcher.add(event(9));
    await tester.pump();

    expect(sent, hasLength(1));
    expect(sent.single, hasLength(10));
    expect(batcher.queued.value, 0);
    batcher.dispose();
  });

  testWidgets('sends 15 s after the first unsent event, not the last one',
      (tester) async {
    final sent = <List<Map<String, dynamic>>>[];
    final batcher = AnalyticsBatcher(send: (b) async => sent.add(b));

    batcher.add(event(0));
    await tester.pump(const Duration(seconds: 10));
    batcher.add(event(1)); // must not push the deadline back
    await tester.pump(const Duration(seconds: 4));
    expect(sent, isEmpty);

    await tester.pump(const Duration(seconds: 1)); // t = 15 s
    expect(sent.map(names), [
      ['e0', 'e1']
    ]);
    batcher.dispose();
  });

  testWidgets('events arriving while a batch is in flight wait for their own '
      'trigger', (tester) async {
    final sent = <List<Map<String, dynamic>>>[];
    final inFlight = Completer<void>();
    final batcher = AnalyticsBatcher(send: (b) async {
      sent.add(b);
      if (sent.length == 1) await inFlight.future;
    });

    for (var i = 0; i < 10; i++) {
      batcher.add(event(i));
    }
    await tester.pump();
    batcher.add(event(10)); // while the first batch is still sending
    inFlight.complete();
    await tester.pump();
    expect(sent, hasLength(1), reason: 'e10 is not swept into a second send');

    await tester.pump(const Duration(seconds: 15));
    expect(sent.map(names).last, ['e10']);
    batcher.dispose();
  });

  testWidgets('a failed batch is retried later, in order, with newer events',
      (tester) async {
    final sent = <List<Map<String, dynamic>>>[];
    var fail = true;
    final batcher = AnalyticsBatcher(send: (b) async {
      if (fail) throw Exception('offline');
      sent.add(b);
    });

    batcher.add(event(0));
    batcher.add(event(1));
    await tester.pump(const Duration(seconds: 15)); // first attempt fails
    expect(sent, isEmpty);
    expect(batcher.queued.value, 2);

    fail = false;
    batcher.add(event(2));
    await tester.pump(const Duration(seconds: 15)); // retry
    expect(sent.map(names), [
      ['e0', 'e1', 'e2']
    ]);
    expect(batcher.batchesSent.value, 1);
    batcher.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/analytics_service.dart';
import '../../service/impression_service.dart';

/// Developer screen: shows every analytics event recorded this session.
/// Useful for verifying the impression-tracking feature task.
class AnalyticsDebugScreen extends StatelessWidget {
  const AnalyticsDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final analytics = Get.find<AnalyticsService>();
    final batcher = Get.find<ImpressionService>().batcher;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics debug'),
        // Delivery state of deal_impression batches (POST /analytics/batch).
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Obx(() => Text(
                  'Impressions waiting: ${batcher.queued.value}'
                  '  ·  Batches sent: ${batcher.batchesSent.value}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                )),
          ),
        ),
      ),
      body: Obx(() {
        final events = analytics.events.reversed.toList();
        if (events.isEmpty) {
          return const Center(child: Text('No events yet'));
        }
        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              dense: true,
              leading: Text(
                event.at.toIso8601String().substring(11, 19),
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade600),
              ),
              title: Text(event.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${event.properties}',
                  style: const TextStyle(fontSize: 12)),
            );
          },
        );
      }),
    );
  }
}

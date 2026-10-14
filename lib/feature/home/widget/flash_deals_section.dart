import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app_config.dart';
import '../../../model/deal_model.dart';
import '../../../routes/routes.dart';
import '../../shared_widget/flash_countdown.dart';
import '../../shared_widget/the_network_image.dart';
import '../../shared_widget/track_impression.dart';

/// Horizontal flash-sale rail. Each card shows a live countdown and turns
/// into a disabled "Expired" card when its sale ends.
class FlashDealsSection extends StatelessWidget {
  final List<DealModel> deals;

  const FlashDealsSection({super.key, required this.deals});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.bolt, color: Colors.red, size: 20),
              SizedBox(width: 4),
              Text('Flash sales',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: deals.length,
            itemBuilder: (context, index) {
              final deal = deals[index];
              return TrackImpression(
                dealId: deal.id,
                source: 'flash_rail',
                position: index,
                child: SizedBox(
                  width: 200,
                  child: FlashExpiryBuilder(
                    endsAt: deal.flashSaleEndsAt,
                    builder: (context, expired) => _FlashDealCard(
                      deal: deal,
                      expired: expired,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FlashDealCard extends StatelessWidget {
  final DealModel deal;
  final bool expired;

  const _FlashDealCard({required this.deal, required this.expired});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0.5,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: expired
            ? null
            : () => Get.toNamed(
                  Routes.dealRoute(deal.id, source: 'flash_rail'),
                  arguments: deal,
                ),
        child: Container(
          foregroundDecoration: expired ? expiredForeground : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TheNetworkImage(
                  url: deal.imageUrl, height: 90, width: double.infinity),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(deal.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('฿${deal.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppConfig.primaryGreen)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: expired
                                ? Colors.grey.shade200
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: expired
                              ? Text('Expired',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800))
                              : FlashCountdownText(
                                  endsAt: deal.flashSaleEndsAt!,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.red.shade700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/order_model.dart';

/// Coloured badge that shows the payment status of an order.
///
/// Only [PaymentStatus.paid] is rendered in green - the badge is driven by
/// the status that the **server** confirmed, never by the client.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final IconData icon;

    switch (status) {
      case PaymentStatus.paid:
        background = const Color(0xFFD7F5DD);
        foreground = const Color(0xFF146C2E);
        icon = Icons.check_circle_rounded;
      case PaymentStatus.pending:
        background = const Color(0xFFFFF0D4);
        foreground = const Color(0xFF8A5A00);
        icon = Icons.schedule_rounded;
      case PaymentStatus.expired:
      case PaymentStatus.cancelled:
        background = const Color(0xFFE6E8EC);
        foreground = const Color(0xFF4A4F57);
        icon = Icons.remove_circle_outline_rounded;
      case PaymentStatus.failed:
        background = const Color(0xFFFDE0E0);
        foreground = const Color(0xFFA32323);
        icon = Icons.error_outline_rounded;
      case PaymentStatus.unknown:
        background = const Color(0xFFE6E8EC);
        foreground = const Color(0xFF4A4F57);
        icon = Icons.help_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

import '../config/app_config.dart';

/// Formats a number as Philippine Peso, e.g. `₱1,500.00`.
String formatPeso(num amount) {
  final double value = amount.toDouble();
  final String fixed = value.toStringAsFixed(2);
  final List<String> parts = fixed.split('.');
  final String grouped = _groupThousands(parts.first);
  return '${AppConfig.currencySymbol}$grouped.${parts.last}';
}

String _groupThousands(String digits) {
  final bool negative = digits.startsWith('-');
  final String bare = negative ? digits.substring(1) : digits;
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < bare.length; i++) {
    if (i > 0 && (bare.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(bare[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a timestamp, e.g. `20 Oct 2026, 3:04 PM`.
String formatOrderDate(DateTime? value) {
  if (value == null) return '-';
  final DateTime local = value.toLocal();
  final String hour = local.hour % 12 == 0 ? '12' : '${local.hour % 12}';
  final String minute = local.minute.toString().padLeft(2, '0');
  final String period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}, '
      '$hour:$minute $period';
}

/// Shortens an order reference so that it fits into a badge.
String shortenReference(String reference, {int maxLength = 8}) {
  if (reference.length <= maxLength) return reference;
  return reference.substring(0, maxLength).toUpperCase();
}

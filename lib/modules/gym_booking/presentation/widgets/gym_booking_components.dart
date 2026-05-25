import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/gym_booking_overview.dart';

Color gymStatusColor(BuildContext context, String? statusCode) {
  return switch (statusCode) {
    '001' => const Color(0xFFE8A838),
    '002' => const Color(0xFF5478A7),
    '003' => Theme.of(context).colorScheme.outline,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

class GymDateSelector extends StatelessWidget {
  const GymDateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.dayCount = 7,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final days = List.generate(
      dayCount.clamp(1, 14),
      (index) => today.add(Duration(days: index)),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: days.map((date) {
          final normalized = DateTime(date.year, date.month, date.day);
          final selected =
              normalized ==
              DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                '${date.month}/${date.day} ${DateFormat('EEE', 'zh_CN').format(date)}',
              ),
              selected: selected,
              onSelected: (_) => onDateChanged(normalized),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class GymStatusBadge extends StatelessWidget {
  const GymStatusBadge({
    super.key,
    required this.label,
    required this.statusCode,
  });

  final String label;
  final String? statusCode;

  @override
  Widget build(BuildContext context) {
    final color = gymStatusColor(context, statusCode);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GymAppointmentTile extends StatelessWidget {
  const GymAppointmentTile({super.key, required this.record, this.onTap});

  final BookingRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusCode = record.effectiveStatusCode;
    final color = gymStatusColor(context, statusCode);

    final venueLabel = record.venueTypeDisplay;
    final flowLabel = record.flowStatusDisplay;
    final violation = record.violation;
    final showViolation = violation != null && violation.isNotEmpty &&
        violation != '否' && violation != '0' && violation != 'null';

    final dateLabel = DateFormat('yyyy-MM-dd EEE', 'zh_CN')
        .format(record.date.toLocal());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.venueName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$dateLabel · ${record.slotLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (venueLabel != null && venueLabel.isNotEmpty ||
                      flowLabel != null && flowLabel.isNotEmpty ||
                      showViolation) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (venueLabel != null && venueLabel.isNotEmpty)
                          _MetaChip(label: venueLabel),
                        if (flowLabel != null && flowLabel.isNotEmpty)
                          _MetaChip(label: flowLabel),
                        if (showViolation)
                          _MetaChip(
                            label: '违约',
                            tone: theme.colorScheme.error,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            GymStatusBadge(
              label: record.effectiveStatus,
              statusCode: statusCode,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.tone});

  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GymSlotTile extends StatelessWidget {
  const GymSlotTile({
    super.key,
    required this.slot,
    required this.onBook,
    this.capacity,
    this.enabled = true,
  });

  final BookableSlot slot;
  final VoidCallback onBook;
  final int? capacity;
  final bool enabled;

  static const _accentColors = [
    Color(0xFF5B8DEF),
    Color(0xFF4CAF50),
    Color(0xFFE8A838),
    Color(0xFFE57373),
    Color(0xFF00ACC1),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor =
        _accentColors[slot.startTime.hashCode.abs() % _accentColors.length];
    final hasPassed = _slotHasPassed(slot);
    final isBookable = enabled && slot.isAvailable && !hasPassed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: isBookable ? accentColor : colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.timeLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  capacity != null && capacity! > 0
                      ? '建议使用人数不超过 $capacity 人'
                      : '该时段当前可预约',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: isBookable ? onBook : null,
            child: Text(
              isBookable
                  ? '预约'
                  : (hasPassed ? '已结束' : '暂不可约'),
            ),
          ),
        ],
      ),
    );
  }
}

bool _slotHasPassed(BookableSlot slot) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final slotDate = DateTime(slot.date.year, slot.date.month, slot.date.day);

  if (slotDate.isBefore(today)) {
    return true;
  }
  if (slotDate.isAfter(today)) {
    return false;
  }

  final parts = slot.startTime.split(':');
  if (parts.length != 2) {
    return false;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return false;
  }
  final start = DateTime(slotDate.year, slotDate.month, slotDate.day, hour, minute);
  return !start.isAfter(now);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/error_display.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/appointment_detail.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../controllers/gym_booking_controller.dart';
import '../widgets/gym_booking_components.dart';

class GymAppointmentDetailPage extends ConsumerWidget {
  const GymAppointmentDetailPage({
    super.key,
    required this.appointmentId,
    this.prefillRecord,
  });

  final String appointmentId;
  final BookingRecord? prefillRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(gymAppointmentDetailProvider(appointmentId));

    return Scaffold(
      appBar: AppBar(title: const Text('预约详情')),
      body: ConstrainedBody(
        child: AsyncValueView(
          value: detailAsync,
          onRetry: () =>
              ref.invalidate(gymAppointmentDetailProvider(appointmentId)),
          loadingLabel: '加载预约详情',
          dataBuilder: (detail) =>
              _DetailContent(detail: detail, prefillRecord: prefillRecord),
        ),
      ),
    );
  }
}

class _DetailContent extends ConsumerWidget {
  const _DetailContent({required this.detail, this.prefillRecord});

  final AppointmentDetail detail;
  final BookingRecord? prefillRecord;

  String get _displayStatus {
    final statusCode = _displayStatusCode;
    if (statusCode != null) {
      return switch (statusCode) {
        '001' => '未使用',
        '002' => '已使用',
        '003' => '已取消',
        _ => detail.status != '未知' ? detail.status : prefillRecord?.status ?? '未知',
      };
    }
    if (detail.status != '未知') {
      return detail.status;
    }
    return prefillRecord?.status ?? detail.status;
  }

  String? get _displayStatusCode {
    // 优先用预约列表里综合过 PAY_STATUS 的状态码，处理"未使用+已取消"脏数据。
    final fromList = prefillRecord?.effectiveStatusCode;
    if (fromList != null) {
      return fromList;
    }
    return detail.statusCode;
  }

  bool get _displayCanCancel {
    if (_displayStatusCode != '001') {
      return false;
    }
    if (prefillRecord?.isCancellable == true) {
      return true;
    }
    return detail.canCancel;
  }

  String _statusHint() {
    return switch (_displayStatusCode) {
      '001' => '当前预约已锁定，可在使用前取消。',
      '002' => '当前预约已经完成使用。',
      '003' => '当前预约已取消，不可再次操作。',
      _ => '预约状态以学校系统最新返回为准。',
    };
  }

  String? _durationLabel() {
    final duration = detail.durationMinutes?.trim();
    if (duration == null || duration.isEmpty) {
      return null;
    }
    return '$duration 分钟';
  }

  String? _cancelReasonLabel() {
    final code = detail.cancelReasonCode?.trim();
    if (code == null || code.isEmpty) {
      return null;
    }
    return switch (code) {
      '0' => '系统默认取消原因',
      _ => code,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = [
      detail.venueType,
      detail.sportName,
      detail.bookingType,
      if (detail.venueCode != null && detail.venueCode!.isNotEmpty)
        '编号 ${detail.venueCode}',
    ].whereType<String>().where((item) => item.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
      children: [
        _HeroCard(
          venueName: detail.venueName,
          address: detail.address,
          status: _displayStatus,
          statusCode: _displayStatusCode,
          hint: _statusHint(),
          date: detail.date,
          slotLabel: detail.slotLabel,
          attendeeCount: detail.attendeeCount,
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map((chip) => _TagChip(label: chip)).toList(),
          ),
        ],
        const SizedBox(height: 12),
        _MetricsGrid(
          items: [
            _MetricItem(
              icon: Icons.event_rounded,
              label: '预约日期',
              value: DateFormat('yyyy-MM-dd EEEE', 'zh_CN').format(detail.date),
            ),
            _MetricItem(
              icon: Icons.schedule_rounded,
              label: '预约时段',
              value: detail.slotLabel,
            ),
            _MetricItem(
              icon: Icons.group_outlined,
              label: '使用人数',
              value:
                  detail.attendeeCount == null || detail.attendeeCount!.isEmpty
                  ? '未提供'
                  : '${detail.attendeeCount} 人',
            ),
            _MetricItem(
              icon: Icons.timelapse_rounded,
              label: '预约时长',
              value: _durationLabel() ?? '以场馆规则为准',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: '场地与联系',
          icon: Icons.pin_drop_outlined,
          rows: [
            _InfoEntry(label: '场地', value: detail.venueName),
            if (detail.address != null && detail.address!.isNotEmpty)
              _InfoEntry(label: '地址', value: detail.address!),
            if (detail.attendeeName != null && detail.attendeeName!.isNotEmpty)
              _InfoEntry(label: '预约人', value: detail.attendeeName!),
            if (detail.phone != null && detail.phone!.isNotEmpty)
              _InfoEntry(label: '联系电话', value: detail.phone!),
            if (detail.department != null && detail.department!.isNotEmpty)
              _InfoEntry(label: '项目', value: detail.department!),
            if (detail.businessWid != null && detail.businessWid!.isNotEmpty)
              _InfoEntry(label: '业务编号', value: detail.businessWid!),
          ],
        ),
        if ((detail.checkInTime?.isNotEmpty ?? false) ||
            (detail.checkOutTime?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 12),
          _InfoCard(
            title: '使用记录',
            icon: Icons.fact_check_outlined,
            rows: [
              if (detail.checkInTime != null && detail.checkInTime!.isNotEmpty)
                _InfoEntry(label: '签到时间', value: detail.checkInTime!),
              if (detail.checkOutTime != null &&
                  detail.checkOutTime!.isNotEmpty)
                _InfoEntry(label: '签退时间', value: detail.checkOutTime!),
            ],
          ),
        ],
        if (_displayStatusCode == '003' &&
            ((detail.cancelTime?.isNotEmpty ?? false) ||
                (_cancelReasonLabel()?.isNotEmpty ?? false))) ...[
          const SizedBox(height: 12),
          _InfoCard(
            title: '取消信息',
            icon: Icons.event_busy_outlined,
            rows: [
              if (_cancelReasonLabel() != null)
                _InfoEntry(label: '取消原因', value: _cancelReasonLabel()!),
              if (detail.cancelTime != null && detail.cancelTime!.isNotEmpty)
                _InfoEntry(label: '取消时间', value: detail.cancelTime!),
            ],
            accentColor: Theme.of(context).colorScheme.error,
          ),
        ],
        if ((detail.rating?.isNotEmpty ?? false) ||
            (detail.reviewContent?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 12),
          _ReviewCard(rating: detail.rating, content: detail.reviewContent),
        ],
        if (_displayCanCancel && _displayStatusCode == '001') ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _confirmCancel(context, ref),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('取消本次预约'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final cancelReason =
        await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            return _CancelReasonDialog(venueName: detail.venueName);
          },
        ) ??
        '';

    if (cancelReason.trim().isEmpty || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    AppSnackBar.show(
      context,
      message: '正在取消预约...',
      tone: AppSnackBarTone.info,
      icon: Icons.hourglass_top_rounded,
      duration: const Duration(seconds: 12),
    );

    final authAsync = ref.read(authControllerProvider);
    final session = authAsync.value?.session;

    if (session == null) {
      messenger.hideCurrentSnackBar();
      AppSnackBar.show(
        context,
        message: '未登录，无法取消预约。',
        tone: AppSnackBarTone.error,
        clearCurrent: false,
      );
      return;
    }

    final result = await ref.read(cancelGymAppointmentUseCaseProvider)(
      session: session,
      appointmentId: detail.id,
      reason: cancelReason.trim(),
    );

    if (!context.mounted) {
      return;
    }

    messenger.hideCurrentSnackBar();
    if (result.isSuccess) {
      AppSnackBar.show(
        context,
        message: '取消预约成功',
        tone: AppSnackBarTone.success,
        icon: Icons.check_circle_rounded,
        clearCurrent: false,
      );

      // 立即在本地把这条预约标记成"已取消"，让首页/列表瞬间显示，
      // 不必等远端 list 接口下一次返回（学校系统偶尔有几秒延迟）。
      ref.read(myGymAppointmentsProvider.notifier).markCancelled(
        appointmentId: detail.id,
        date: detail.date,
        slotLabel: detail.slotLabel,
      );

      ref.invalidate(gymAppointmentDetailProvider(detail.id));
      ref.invalidate(myGymAppointmentsProvider);
    } else {
      AppSnackBar.show(
        context,
        message: formatError(result.failureOrNull!).message,
        tone: AppSnackBarTone.error,
        clearCurrent: false,
      );
    }
  }
}

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog({required this.venueName});

  final String venueName;

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '请填写取消原因');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('填写取消原因'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('请填写取消「${widget.venueName}」的原因，提交后将同步到学校系统。'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '取消原因',
              hintText: '例如：时间冲突、临时有事',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _submit,
          child: const Text('提交取消'),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.venueName,
    required this.address,
    required this.status,
    required this.statusCode,
    required this.hint,
    required this.date,
    required this.slotLabel,
    required this.attendeeCount,
  });

  final String venueName;
  final String? address;
  final String status;
  final String? statusCode;
  final String hint;
  final DateTime date;
  final String slotLabel;
  final String? attendeeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = gymStatusColor(context, statusCode);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.36) ??
                colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              venueName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (address != null && address!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                address!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: '预约日期',
                    value: DateFormat('MM-dd EEE', 'zh_CN').format(date),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroStat(label: '预约时段', value: slotLabel),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _HeroStat(
              label: '使用提示',
              value: attendeeCount == null || attendeeCount!.isEmpty
                  ? hint
                  : '本次预约 $attendeeCount 人，$hint',
              wide: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _MetricItem {
  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.items});

  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((item) => _MetricCard(item: item)).toList(),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _MetricItem item;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width > 560 ? (width - 64) / 2 : (width - 52) / 2;
    final theme = Theme.of(context);

    return SizedBox(
      width: cardWidth,
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              item.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoEntry {
  const _InfoEntry({required this.label, required this.value});

  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.accentColor,
  });

  final String title;
  final IconData icon;
  final List<_InfoEntry> rows;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map((row) => _InfoRow(label: row.label, value: row.value)),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.rating, required this.content});

  final String? rating;
  final String? content;

  @override
  Widget build(BuildContext context) {
    final score = double.tryParse(rating ?? '');
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '评价信息',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (score != null) ...[
            Row(
              children: [
                ...List.generate(5, (index) {
                  final active = score >= index + 1;
                  return Icon(
                    active ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18,
                    color: const Color(0xFFE8A838),
                  );
                }),
                const SizedBox(width: 8),
                Text(
                  score.toStringAsFixed(
                    score.truncateToDouble() == score ? 0 : 1,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
          if (content != null && content!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(content!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

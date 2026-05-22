import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/error_display.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../domain/entities/electricity_dashboard.dart';
import '../controllers/electricity_controller.dart';

class ElectricityPage extends ConsumerWidget {
  const ElectricityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final electricityAsync = ref.watch(electricityControllerProvider);
    final dashboard = electricityAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('宿舍电量'),
        actions: [
          IconButton(
            onPressed: () => _showBindingEditor(
              context,
              ref,
              dashboard?.binding ?? ElectricityRoomBinding.defaultBinding,
            ),
            icon: const Icon(Icons.edit_outlined),
            tooltip: '修改宿舍',
          ),
        ],
      ),
      body: ConstrainedBody(
        child: AsyncValueView(
          value: electricityAsync,
          onRetry: () =>
              ref.read(electricityControllerProvider.notifier).refresh(),
          loadingLabel: '电量数据同步中',
          dataBuilder: (dashboard) => RefreshIndicator(
            onRefresh: () =>
                ref.read(electricityControllerProvider.notifier).refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                _BalanceHeroCard(dashboard: dashboard),
                const SizedBox(height: 16),
                _MetricsGrid(dashboard: dashboard),
                const SizedBox(height: 16),
                _PeriodSelector(
                  selectedPeriod: dashboard.selectedPeriod,
                  onSelected: (period) => ref
                      .read(electricityControllerProvider.notifier)
                      .selectPeriod(period),
                ),
                const SizedBox(height: 16),
                _RechargeTrendCard(dashboard: dashboard),
                const SizedBox(height: 16),
                _RechargeRecordsCard(dashboard: dashboard),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showBindingEditor(
    BuildContext context,
    WidgetRef ref,
    ElectricityRoomBinding initialBinding,
  ) async {
    final buildingController = TextEditingController(
      text: initialBinding.building,
    );
    final roomController = TextEditingController(
      text: initialBinding.roomNumber,
    );
    String? submitError;
    var isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '宿舍设置',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '修改后会重新请求当前宿舍的剩余电量和充值记录。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: buildingController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '楼栋',
                      hintText: '例如 K',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roomController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '房号',
                      hintText: '例如 503',
                    ),
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      submitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setState(() {
                                submitError = null;
                                isSubmitting = true;
                              });

                              try {
                                await ref
                                    .read(
                                      electricityControllerProvider.notifier,
                                    )
                                    .updateBinding(
                                      building: buildingController.text,
                                      roomNumber: roomController.text,
                                    );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              } catch (error) {
                                setState(() {
                                  submitError = formatError(error).message;
                                  isSubmitting = false;
                                });
                              }
                            },
                      child: Text(isSubmitting ? '保存中...' : '保存并刷新'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    buildingController.dispose();
    roomController.dispose();
  }
}

class _BalanceHeroCard extends StatelessWidget {
  const _BalanceHeroCard({required this.dashboard});

  final ElectricityDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 保持暖橙作为电费模块品牌色，但在深色下回落到 tertiaryContainer，
    // 不再让浅色硬编码 #FFF0CF 在深色背景上显得发灰。
    final gradientFrom =
        isDark ? theme.colorScheme.tertiaryContainer : const Color(0xFFFFF0CF);
    final gradientTo = isDark
        ? Color.lerp(
                theme.colorScheme.tertiaryContainer,
                theme.colorScheme.surface,
                0.4,
              ) ??
              theme.colorScheme.tertiaryContainer
        : const Color(0xFFFFF8EA);
    const accent = Color(0xFFD28A19);
    final accentColor = isDark ? theme.colorScheme.tertiary : accent;
    final foreground =
        isDark ? theme.colorScheme.onTertiaryContainer : Colors.black;

    return SurfaceCard(
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [gradientFrom, gradientTo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.bolt_rounded,
                      color: accentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dashboard.binding.displayLabel,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dashboard.balance.apartName.isEmpty
                              ? dashboard.balance.schoolName
                              : '${dashboard.balance.schoolName} · ${dashboard.balance.apartName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: foreground.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                '${dashboard.balance.remainingKwh.toStringAsFixed(2)} 度',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '最近更新 ${DateFormat('yyyy-MM-dd HH:mm').format(dashboard.balance.updatedAt)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.dashboard});

  final ElectricityDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: '累计用电',
            value: '${dashboard.balance.totalUsedKwh.toStringAsFixed(2)} 度',
            accent: const Color(0xFF2F766F),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: '充值总额',
            value: '¥${dashboard.totalRechargeAmount.toStringAsFixed(2)}',
            accent: const Color(0xFFB86E1F),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: '充值笔数',
            value: '${dashboard.totalRecords}',
            accent: const Color(0xFF5478A7),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selectedPeriod,
    required this.onSelected,
  });

  final ElectricityChargePeriod selectedPeriod;
  final ValueChanged<ElectricityChargePeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in ElectricityChargePeriod.values) ...[
            ChoiceChip(
              label: Text(period.label),
              selected: period == selectedPeriod,
              onSelected: (_) => onSelected(period),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _RechargeTrendCard extends StatelessWidget {
  const _RechargeTrendCard({required this.dashboard});

  final ElectricityDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final bars = _RechargeTrendBar.aggregate(
      dashboard.records,
      maxBars: dashboard.selectedPeriod == ElectricityChargePeriod.threeMonths
          ? 3
          : 6,
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '充值趋势',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                dashboard.selectedPeriod.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '按月份汇总充值金额，适合快速看最近一段时间的补电频率。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          if (bars.isEmpty)
            const _EmptyState(message: '当前周期没有可展示的充值记录。')
          else
            _RechargeBarChart(bars: bars),
        ],
      ),
    );
  }
}

class _RechargeBarChart extends StatelessWidget {
  const _RechargeBarChart({required this.bars});

  final List<_RechargeTrendBar> bars;

  @override
  Widget build(BuildContext context) {
    final maxAmount = bars.fold<double>(
      0,
      (current, item) => math.max(current, item.amountYuan),
    );

    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '¥${bar.amountYuan.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: maxAmount == 0
                          ? 10
                          : 16 + (bar.amountYuan / maxAmount) * 82,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD28A19).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      bar.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RechargeRecordsCard extends StatelessWidget {
  const _RechargeRecordsCard({required this.dashboard});

  final ElectricityDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '充值记录',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '共 ${dashboard.totalRecords} 条，当前展示 ${dashboard.records.length} 条。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (dashboard.records.isEmpty)
            const _EmptyState(message: '当前周期没有查到充值记录。')
          else
            for (final record in dashboard.records) ...[
              _RechargeRecordTile(record: record),
              if (record != dashboard.records.last) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
              ],
            ],
        ],
      ),
    );
  }
}

class _RechargeRecordTile extends StatelessWidget {
  const _RechargeRecordTile({required this.record});

  final ElectricityRechargeRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFD28A19).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            '¥${record.amountYuan.toStringAsFixed(0)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: const Color(0xFFD28A19),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.paymentMethodLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('yyyy-MM-dd HH:mm').format(record.paidAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '订单 ${record.orderCode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2F766F).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '已充值',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF2F766F),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RechargeTrendBar {
  const _RechargeTrendBar({required this.label, required this.amountYuan});

  final String label;
  final double amountYuan;

  static List<_RechargeTrendBar> aggregate(
    List<ElectricityRechargeRecord> records, {
    required int maxBars,
  }) {
    final sums = <DateTime, double>{};
    for (final record in records) {
      final month = DateTime(record.paidAt.year, record.paidAt.month);
      sums[month] = (sums[month] ?? 0) + record.amountYuan;
    }

    final entries = sums.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final start = entries.length > maxBars ? entries.length - maxBars : 0;

    return entries.sublist(start).map((entry) {
      return _RechargeTrendBar(
        label: DateFormat('M月').format(entry.key),
        amountYuan: entry.value,
      );
    }).toList();
  }
}

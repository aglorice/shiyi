import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/error_display.dart';
import '../../../../core/error/failure.dart';
import '../../../../shared/widgets/pixel_pet.dart';
import '../../../../shared/widgets/session_expired_dialog.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../electricity/domain/entities/electricity_dashboard.dart';
import '../../../electricity/presentation/controllers/electricity_controller.dart';
import '../../../gym_booking/domain/entities/gym_booking_overview.dart';
import '../../../gym_booking/presentation/controllers/gym_booking_controller.dart';
import '../../../gym_booking/presentation/widgets/gym_booking_components.dart';
import '../../../schedule/domain/entities/schedule_snapshot.dart';
import '../../../schedule/presentation/controllers/schedule_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).value;
    final scheduleAsync = ref.watch(scheduleControllerProvider);
    final electricityAsync = ref.watch(electricityControllerProvider);
    final appointmentsAsync = ref.watch(myGymAppointmentsProvider);
    final syncState = _HomeSyncState.fromAsyncValue(scheduleAsync);
    final preferences = ref.watch(appPreferencesControllerProvider);
    final petType = PixelPetType.fromName(preferences.pixelPet);
    final rawDisplayName = authState?.session?.displayName.trim() ?? '';
    final displayName = "宫园薰";
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.read(scheduleControllerProvider.notifier).refresh(),
          ref.read(electricityControllerProvider.notifier).refresh(),
          ref.read(myGymAppointmentsProvider.notifier).refresh(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        children: [
          _HomeHero(
            displayName: displayName,
            dateLabel: dateStr,
            syncState: syncState,
            petType: petType,
          ),
          const SizedBox(height: 14),
          _TodayCourseCard(scheduleAsync: scheduleAsync),
          const SizedBox(height: 10),
          _ElectricityPreviewCard(electricityAsync: electricityAsync),
          const SizedBox(height: 10),
          _GymAppointmentsPreviewCard(appointmentsAsync: appointmentsAsync),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '常用入口',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const _QuickActions(),
          const SizedBox(height: 16),
          _HomeFooter(
            syncState: syncState,
            onRetry: () =>
                ref.read(scheduleControllerProvider.notifier).refresh(),
          ),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.displayName,
    required this.dateLabel,
    required this.syncState,
    required this.petType,
  });

  final String displayName;
  final String dateLabel;
  final _HomeSyncState syncState;
  final PixelPetType petType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.52) ??
                colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$displayName，你好',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(syncState.icon, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          syncState.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PixelPet(type: petType),
          ],
        ),
      ),
    );
  }
}

class _TodayCourseCard extends StatelessWidget {
  const _TodayCourseCard({required this.scheduleAsync});

  final AsyncValue<ScheduleSnapshot> scheduleAsync;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: switch (scheduleAsync) {
        AsyncData(:final value) => _buildContent(context, value),
        AsyncError() => _buildPlaceholder(
          context,
          text: '课程数据暂时不可用',
          icon: Icons.event_busy_rounded,
        ),
        _ => _buildPlaceholder(
          context,
          text: '正在同步课程...',
          icon: Icons.autorenew_rounded,
        ),
      },
    );
  }

  Widget _buildPlaceholder(
    BuildContext context, {
    required String text,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天的课',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, ScheduleSnapshot snapshot) {
    final entries = snapshot.sessionsForDay(
      DateTime.now().weekday,
      week: snapshot.displayWeek,
    );

    if (entries.isEmpty) {
      return _buildPlaceholder(
        context,
        text: '今天没课，好好休息',
        icon: Icons.free_breakfast_rounded,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const maxVisible = 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '今天的课',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${entries.length} 节',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < entries.length && i < maxVisible; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          _SessionRow(
            entry: entries[i],
            accentColor: _SessionRow.colorForIndex(i),
          ),
        ],
        if (entries.length > maxVisible) ...[
          const SizedBox(height: 8),
          Text(
            '还有 ${entries.length - maxVisible} 节课…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.entry, required this.accentColor});

  final ScheduleEntry entry;
  final Color accentColor;

  static const _accentColors = [
    Color(0xFF5B8DEF),
    Color(0xFFE8A838),
    Color(0xFF4CAF50),
    Color(0xFFE57373),
    Color(0xFFAB47BC),
  ];

  static Color colorForIndex(int index) =>
      _accentColors[index % _accentColors.length];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              entry.session.startTime,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.course.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    entry.session.location.fullName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
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

class _ElectricityPreviewCard extends StatelessWidget {
  const _ElectricityPreviewCard({required this.electricityAsync});

  final AsyncValue<ElectricityDashboard> electricityAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: InkWell(
        onTap: () => context.push('/electricity'),
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (electricityAsync) {
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD28A19).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 20,
                        color: Color(0xFFD28A19),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '宿舍电量',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value.binding.displayLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '${value.balance.remainingKwh.toStringAsFixed(2)} 度',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFD28A19),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '最近更新 ${DateFormat('MM-dd HH:mm').format(value.balance.updatedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            AsyncError(:final error) => Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    formatError(error).icon,
                    size: 20,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '宿舍电量',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatError(error).message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _ => Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD28A19).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bolt_outlined,
                    size: 20,
                    color: Color(0xFFD28A19),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '宿舍电量',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '正在同步剩余度数...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

class _GymAppointmentsPreviewCard extends StatelessWidget {
  const _GymAppointmentsPreviewCard({required this.appointmentsAsync});

  final AsyncValue<List<BookingRecord>> appointmentsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/gym-booking/my'),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF2D8C8F,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.event_note_rounded,
                            size: 20,
                            color: Color(0xFF2D8C8F),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '我的场馆预约',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => context.push('/gym-booking/my'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  foregroundColor: const Color(0xFF2D8C8F),
                ),

                label: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          switch (appointmentsAsync) {
            AsyncData(:final value) =>
              value.isEmpty
                  ? _HomeGymEmptyState(
                      onBook: () => context.push('/gym-booking'),
                    )
                  : Column(
                      children: [
                        for (final record in value.take(3)) ...[
                          _HomeAppointmentRow(record: record),
                          if (record != value.take(3).last)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Divider(
                                height: 1,
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            AsyncError(:final error) => Row(
              children: [
                Icon(
                  formatError(error).icon,
                  size: 18,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    formatError(error).message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          },
        ],
      ),
    );
  }
}

class _HomeAppointmentRow extends StatelessWidget {
  const _HomeAppointmentRow({required this.record});

  final BookingRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = gymStatusColor(context, record.statusCode);

    return InkWell(
      onTap: () =>
          context.push('/gym-booking/appointment/${record.id}', extra: record),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateFormat('MM-dd', 'zh_CN').format(record.date.toLocal())}  ${record.slotLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GymStatusBadge(
                label: record.status,
                statusCode: record.statusCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeGymEmptyState extends StatelessWidget {
  const _HomeGymEmptyState({required this.onBook});

  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.sports_tennis_outlined,
              size: 32,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '暂无预约记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: onBook, child: const Text('去预约')),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = [
      _QuickActionItem(
        icon: Icons.school_outlined,
        title: '成绩',
        color: const Color(0xFF5478A7),
        onTap: () => context.push('/grades'),
      ),
      _QuickActionItem(
        icon: Icons.assignment_outlined,
        title: '考试',
        color: const Color(0xFFC07A30),
        onTap: () => context.push('/exams'),
      ),
      _QuickActionItem(
        icon: Icons.bolt_outlined,
        title: '电量',
        color: const Color(0xFFD28A19),
        onTap: () => context.push('/electricity'),
      ),
      _QuickActionItem(
        icon: Icons.grid_view_outlined,
        title: '服务',
        color: const Color(0xFF3A6B4F),
        onTap: () => context.push('/services'),
      ),
      _QuickActionItem(
        icon: Icons.sports_tennis_outlined,
        title: '场馆',
        color: const Color(0xFF6B5B95),
        onTap: () => context.push('/gym-booking'),
      ),
    ];

    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(item.icon, color: item.color, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickActionItem {
  const _QuickActionItem({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
}

class _HomeFooter extends ConsumerWidget {
  const _HomeFooter({required this.syncState, required this.onRetry});

  final _HomeSyncState syncState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(syncState.icon, size: 14, color: syncState.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              syncState.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (syncState.isSessionExpired)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: () => showSessionExpiredDialog(context, ref),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('重新登录'),
              ),
            )
          else if (syncState.showRetry)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('重试'),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeSyncState {
  const _HomeSyncState({
    required this.label,
    required this.message,
    required this.icon,
    required this.color,
    this.showRetry = false,
    this.isSessionExpired = false,
  });

  final String label;
  final String message;
  final IconData icon;
  final Color color;
  final bool showRetry;
  final bool isSessionExpired;

  factory _HomeSyncState.fromAsyncValue(
    AsyncValue<ScheduleSnapshot> scheduleAsync,
  ) {
    return switch (scheduleAsync) {
      AsyncData() => const _HomeSyncState(
        label: '教务数据已同步',
        message: '下拉首页可以重新同步，常用功能已经可以直接使用。',
        icon: Icons.check_circle_outline_rounded,
        color: Color(0xFF0F6A71),
      ),
      AsyncError(:final error) when error is SessionExpiredFailure =>
        const _HomeSyncState(
          label: '登录已过期',
          message: '学校门户登录态已失效，点击重新登录或退出。',
          icon: Icons.lock_outline,
          color: Color(0xFFB91C1C),
          isSessionExpired: true,
        ),
      AsyncError() => const _HomeSyncState(
        label: '教务数据暂不可用',
        message: '不影响你进入成绩、考试和课表，必要时可以重新同步。',
        icon: Icons.sync_problem_rounded,
        color: Color(0xFFB96A1F),
        showRetry: true,
      ),
      _ => const _HomeSyncState(
        label: '正在同步教务数据',
        message: '首页不再展示复杂课程信息，同步完成后可直接进入课表。',
        icon: Icons.autorenew_rounded,
        color: Color(0xFF5478A7),
      ),
    };
  }
}

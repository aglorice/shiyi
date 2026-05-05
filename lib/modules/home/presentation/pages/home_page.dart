import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/layout/breakpoints.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/error/failure.dart';
import '../../../../shared/widgets/pixel_pet.dart';
import '../../../../shared/widgets/session_expired_dialog.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../electricity/domain/entities/electricity_dashboard.dart';
import '../../../electricity/presentation/controllers/electricity_controller.dart';
import '../../../gym_booking/domain/entities/gym_booking_overview.dart';
import '../../../gym_booking/presentation/controllers/gym_booking_controller.dart';
import '../../../gym_booking/presentation/widgets/gym_booking_components.dart';
import '../../../schedule/domain/entities/schedule_snapshot.dart';
import '../../../schedule/presentation/controllers/schedule_controller.dart';
import '../../../school_news/presentation/controllers/school_news_controller.dart';
import '../../../school_news/presentation/models/school_news_feed_state.dart';
import '../../domain/entities/hitokoto_quote.dart';
import '../controllers/hitokoto_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).value;
    final scheduleAsync = ref.watch(scheduleControllerProvider);
    final electricityAsync = ref.watch(electricityControllerProvider);
    final appointmentsAsync = ref.watch(myGymAppointmentsProvider);
    final schoolNewsAsync = ref.watch(schoolNewsControllerProvider);
    final hitokotoAsync = ref.watch(hitokotoControllerProvider);
    final syncState = _HomeSyncState.fromAsyncValue(scheduleAsync);
    final preferences = ref.watch(appPreferencesControllerProvider);
    final petType = PixelPetType.fromName(preferences.pixelPet);
    final rawDisplayName = authState?.session?.displayName.trim() ?? '';
    final displayName = rawDisplayName.isEmpty ? '同学' : rawDisplayName;
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final useDesktopOverview =
            MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop &&
            constraints.maxWidth >= 760;

        final children = useDesktopOverview
            ? <Widget>[
                _HomeHero(
                  displayName: displayName,
                  dateLabel: dateStr,
                  syncState: syncState,
                  petType: petType,
                  quoteAsync: hitokotoAsync,
                ),
                const SizedBox(height: 18),
                _SchoolNewsOverviewCard(newsAsync: schoolNewsAsync),
                const SizedBox(height: 14),
                _DesktopOverviewGrid(
                  scheduleAsync: scheduleAsync,
                  electricityAsync: electricityAsync,
                  appointmentsAsync: appointmentsAsync,
                ),
                const SizedBox(height: 24),
                const _HomeQuickActionsSection(),
                const SizedBox(height: 16),
                _HomeFooter(
                  syncState: syncState,
                  onRetry: () =>
                      ref.read(scheduleControllerProvider.notifier).refresh(),
                ),
              ]
            : <Widget>[
                _HomeHero(
                  displayName: displayName,
                  dateLabel: dateStr,
                  syncState: syncState,
                  petType: petType,
                  quoteAsync: hitokotoAsync,
                ),
                const SizedBox(height: 14),
                _SchoolNewsOverviewCard(newsAsync: schoolNewsAsync),
                const SizedBox(height: 10),
                _MobileOverviewGrid(
                  scheduleAsync: scheduleAsync,
                  electricityAsync: electricityAsync,
                ),
                const SizedBox(height: 10),
                _GymAppointmentsPreviewCard(
                  appointmentsAsync: appointmentsAsync,
                ),
                const SizedBox(height: 22),
                const _HomeQuickActionsSection(),
                const SizedBox(height: 16),
                _HomeFooter(
                  syncState: syncState,
                  onRetry: () =>
                      ref.read(scheduleControllerProvider.notifier).refresh(),
                ),
              ];

        return RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(scheduleControllerProvider.notifier).refresh(),
              ref.read(electricityControllerProvider.notifier).refresh(),
              ref.read(myGymAppointmentsProvider.notifier).refresh(),
              ref.read(schoolNewsControllerProvider.notifier).refresh(),
              ref.read(hitokotoControllerProvider.notifier).refresh(),
            ]);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
            children: children,
          ),
        );
      },
    );
  }
}

class _SchoolNewsOverviewCard extends StatelessWidget {
  const _SchoolNewsOverviewCard({required this.newsAsync});

  final AsyncValue<SchoolNewsFeedState> newsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accent = Color(0xFF0A5D63);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/school-news'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.newspaper_rounded,
                  color: accent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: switch (newsAsync) {
                  AsyncData(:final value) => _buildContent(context, value),
                  AsyncError(:final error) => _buildError(context, error),
                  _ => _buildLoading(context),
                },
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, SchoolNewsFeedState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final latest = state.items.isEmpty ? null : state.items.first;
    final dateLabel = latest == null
        ? '官方动态'
        : DateFormat('MM月dd日', 'zh_CN').format(latest.publishedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '学校要闻',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          latest?.title ?? '查看五邑大学最新学校要闻',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.42,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '官方动态 · $dateLabel',
          style: theme.textTheme.labelSmall?.copyWith(
            color: const Color(0xFF0A5D63),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '学校要闻',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '正在同步官方动态...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '学校要闻',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatError(error).message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.42,
          ),
        ),
      ],
    );
  }
}

class _MobileOverviewGrid extends StatelessWidget {
  const _MobileOverviewGrid({
    required this.scheduleAsync,
    required this.electricityAsync,
  });

  final AsyncValue<ScheduleSnapshot> scheduleAsync;
  final AsyncValue<ElectricityDashboard> electricityAsync;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            children: [
              _TodayCourseCard(scheduleAsync: scheduleAsync),
              const SizedBox(height: 10),
              _ElectricityPreviewCard(electricityAsync: electricityAsync),
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _TodayCourseCard(scheduleAsync: scheduleAsync)),
              const SizedBox(width: 10),
              Expanded(
                child: _ElectricityPreviewCard(
                  electricityAsync: electricityAsync,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopOverviewGrid extends StatelessWidget {
  const _DesktopOverviewGrid({
    required this.scheduleAsync,
    required this.electricityAsync,
    required this.appointmentsAsync,
  });

  final AsyncValue<ScheduleSnapshot> scheduleAsync;
  final AsyncValue<ElectricityDashboard> electricityAsync;
  final AsyncValue<List<BookingRecord>> appointmentsAsync;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final columnWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: columnWidth,
              child: _TodayCourseCard(scheduleAsync: scheduleAsync),
            ),
            SizedBox(
              width: columnWidth,
              child: _ElectricityPreviewCard(
                electricityAsync: electricityAsync,
              ),
            ),
            SizedBox(
              width: columnWidth,
              child: _GymAppointmentsPreviewCard(
                appointmentsAsync: appointmentsAsync,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.displayName,
    required this.dateLabel,
    required this.syncState,
    required this.petType,
    required this.quoteAsync,
  });

  final String displayName;
  final String dateLabel;
  final _HomeSyncState syncState;
  final PixelPetType petType;
  final AsyncValue<HitokotoQuote> quoteAsync;

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
            _HeroPetQuote(type: petType, quoteAsync: quoteAsync),
          ],
        ),
      ),
    );
  }
}

class _HeroPetQuote extends ConsumerWidget {
  const _HeroPetQuote({required this.type, required this.quoteAsync});

  final PixelPetType type;
  final AsyncValue<HitokotoQuote> quoteAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = quoteAsync.asData?.value;
    final hasQuote = quote != null && quote.text.trim().isNotEmpty;
    final width = MediaQuery.sizeOf(context).width;

    return SizedBox(
      width: width >= AppBreakpoints.desktop ? 220 : 180,
      height: hasQuote ? 94 : 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: 0, bottom: 0, child: _EasterEggPet(type: type)),
          if (hasQuote)
            Positioned(
              right: 54,
              top: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    ref.read(hitokotoControllerProvider.notifier).refresh(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _HitokotoBubble(
                    key: ValueKey(quote.uuid ?? quote.text),
                    text: quote.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HitokotoBubble extends StatelessWidget {
  const _HitokotoBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 90, maxWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF274245),
              fontSize: 10.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: -4,
          child: Transform.rotate(
            angle: 0.75,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EasterEggPet extends StatefulWidget {
  const _EasterEggPet({required this.type});

  final PixelPetType type;

  @override
  State<_EasterEggPet> createState() => _EasterEggPetState();
}

class _EasterEggPetState extends State<_EasterEggPet> {
  static const _messages = [
    '今天的小纸条：把最难的事拆成一小块就好。',
    '课间风路过时，记得给自己留三分钟空白。',
    '今日幸运色：晴空蓝，适合开始一件拖了很久的小事。',
    '你发现了藏起来的便签，奖励自己慢一点也可以。',
    '今日隐藏任务：认真吃一顿饭，别让忙碌偷走晚餐。',
  ];

  int _tapCount = 0;
  Timer? _tapResetTimer;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
    super.dispose();
  }

  void _handleTap() {
    _tapResetTimer?.cancel();
    _tapCount += 1;
    if (_tapCount >= 6) {
      _tapCount = 0;
      _showEasterEgg();
      return;
    }
    _tapResetTimer = Timer(const Duration(milliseconds: 1600), () {
      _tapCount = 0;
    });
  }

  void _showEasterEgg() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final previousEntry = _overlayEntry;
    _overlayEntry = null;
    previousEntry?.remove();
    final message =
        _messages[DateTime.now().millisecondsSinceEpoch % _messages.length];
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _HomeEasterEggToast(
        type: widget.type,
        message: message,
        onDismissed: () {
          if (_overlayEntry == entry) {
            _overlayEntry = null;
            entry.remove();
          }
        },
      ),
    );
    _overlayEntry = entry;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onLongPress: _showEasterEgg,
      child: PixelPet(type: widget.type),
    );
  }
}

class _HomeEasterEggToast extends StatefulWidget {
  const _HomeEasterEggToast({
    required this.type,
    required this.message,
    required this.onDismissed,
  });

  final PixelPetType type;
  final String message;
  final VoidCallback onDismissed;

  @override
  State<_HomeEasterEggToast> createState() => _HomeEasterEggToastState();
}

class _HomeEasterEggToastState extends State<_HomeEasterEggToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 240),
    )..forward();
    _dismissTimer = Timer(const Duration(milliseconds: 3600), _dismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissed) return;
    _dismissed = true;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final top = MediaQuery.viewPaddingOf(context).top + 18;

    return Positioned(
      left: 18,
      right: 18,
      top: top,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = Curves.easeOutCubic.transform(_controller.value);
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, -18 + 18 * value),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.surface,
                    Color.lerp(
                          colorScheme.surface,
                          colorScheme.tertiaryContainer,
                          0.45,
                        ) ??
                        colorScheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  const _EasterEggParticles(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 46,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Transform.scale(
                                scale: 0.64,
                                child: PixelPet(type: widget.type),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '隐藏小纸条',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.message,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.42,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EasterEggParticles extends StatelessWidget {
  const _EasterEggParticles();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = [
      colorScheme.primary,
      const Color(0xFFE07A8A),
      const Color(0xFFB97834),
      const Color(0xFF2F8C72),
    ];

    return Positioned.fill(
      child: Stack(
        children: [
          for (var i = 0; i < 9; i++)
            Positioned(
              left: 18.0 + i * 39,
              top: i.isEven ? 9 : 56,
              child: Icon(
                i % 3 == 0
                    ? Icons.auto_awesome_rounded
                    : Icons.favorite_rounded,
                size: i.isEven ? 10 : 8,
                color: colors[i % colors.length].withValues(alpha: 0.18),
              ),
            ),
        ],
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

class _HomeQuickActionsSection extends StatelessWidget {
  const _HomeQuickActionsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
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
      AsyncData(:final value) when value.loadError != null =>
        const _HomeSyncState(
          label: '教务数据暂不可用',
          message: '不影响你进入成绩、考试和课表，必要时可以重新同步。',
          icon: Icons.sync_problem_rounded,
          color: Color(0xFFB96A1F),
          showRetry: true,
        ),
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

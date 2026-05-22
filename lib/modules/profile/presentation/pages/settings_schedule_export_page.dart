import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';
import '../../../schedule/domain/entities/schedule_snapshot.dart';
import '../../../schedule/presentation/controllers/schedule_controller.dart';

/// 「导出整学期课表」页。
///
/// 设计目标：一眼看懂、一键完成。
/// - 顶部一块大数字面板：当前学期 / 课程数 / 节次数。
/// - 中部三个数字小条：FREQ=WEEKLY、当前周锚点、最末周。
/// - 底部一个大按钮，状态实时反馈（"未设置周次" / "暂无课程" / "导出"）。
class SettingsScheduleExportPage extends ConsumerStatefulWidget {
  const SettingsScheduleExportPage({super.key});

  @override
  ConsumerState<SettingsScheduleExportPage> createState() =>
      _SettingsScheduleExportPageState();
}

class _SettingsScheduleExportPageState
    extends ConsumerState<SettingsScheduleExportPage> {
  bool _busy = false;
  bool _onlyFuture = true;

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleControllerProvider);
    final preferences = ref.watch(appPreferencesControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('导出课表')),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              '课表加载失败：$error',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
        data: (snapshot) {
          final referenceWeek = preferences.computedScheduleWeek;
          final lastWeek = snapshot.maxWeek;
          final canExport =
              snapshot.entries.isNotEmpty && referenceWeek != null;
          return ListView(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.pageBottomGap,
            ),
            children: [
              _HeroPanel(snapshot: snapshot),
              PageSection(
                title: '导出范围',
                divider: false,
                children: [
                  _MetaRow(
                    icon: Icons.calendar_view_month_outlined,
                    label: '学期',
                    value: snapshot.term.name,
                  ),
                  _MetaRow(
                    icon: Icons.today_outlined,
                    label: '本周锚点',
                    value: referenceWeek == null
                        ? '未设置'
                        : '第 $referenceWeek 周',
                    warn: referenceWeek == null,
                  ),
                  _MetaRow(
                    icon: Icons.event_available_outlined,
                    label: '到第几周',
                    value: '第 $lastWeek 周',
                  ),
                  _MetaRow(
                    icon: Icons.repeat_rounded,
                    label: '生成方式',
                    value: '每周一条独立事件',
                  ),
                  _ToggleRow(
                    icon: Icons.skip_next_rounded,
                    label: '只导出今天之后的课',
                    value: _onlyFuture,
                    onChanged: (v) => setState(() => _onlyFuture = v),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageH,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: !canExport || _busy
                        ? null
                        : () => _onExport(snapshot),
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(
                      _busy
                          ? '生成中…'
                          : canExport
                              ? '生成 ICS 并分享'
                              : referenceWeek == null
                                  ? '请先在课表设置当前第几周'
                                  : '当前学期没有可导出的课程',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (referenceWeek == null) ...[
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH,
                  ),
                  child: Text(
                    '需要先在课表页选过一次"当前第几周"才能算出准确日期。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _onExport(ScheduleSnapshot snapshot) async {
    if (_busy) return;
    final preferences = ref.read(appPreferencesControllerProvider);
    final week = preferences.computedScheduleWeek;
    if (week == null) {
      AppSnackBar.show(
        context,
        message: '请先在课表页设置当前第几周',
        tone: AppSnackBarTone.error,
      );
      return;
    }

    setState(() => _busy = true);

    final exporter = ref.read(scheduleIcsExporterProvider);
    try {
      final skipped = <String>[];
      final ics = exporter.buildIcs(
        snapshot: snapshot,
        referenceDate: DateTime.now(),
        referenceWeek: week,
        skipped: skipped,
        timing: preferences.scheduleTiming,
        onlyFutureFrom: _onlyFuture ? _startOfThisWeek() : null,
      );
      if (ics == null) {
        if (mounted) {
          AppSnackBar.show(
            context,
            message: skipped.isEmpty
                ? '当前学期没有课程可导出'
                : '没有可识别的时间，原因：${skipped.first}',
            tone: AppSnackBarTone.error,
          );
        }
        return;
      }

      final file = await exporter.writeToTemp(
        ics: ics,
        snapshot: snapshot,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: 'text/calendar',
              name: file.uri.pathSegments.last,
            ),
          ],
          subject: '${snapshot.term.name} 课表',
          text: '由 uni_yi 导出，包含本学期 ${snapshot.entries.length} 节课。',
        ),
      );
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: '导出失败：$error',
          tone: AppSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 本周一 00:00。导出"今天之后的课"用这个当 cutoff，
  /// 这样本周已经过去的几天（如周一/周二）的课也会保留下来。
  DateTime _startOfThisWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // weekday: 1=周一, 7=周日
    return today.subtract(Duration(days: today.weekday - 1));
  }
}

/// 顶部「大数字」面板：学期名 + 课程数 + 节次数。
/// 直接铺在背景上，不画卡。
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.snapshot});

  final ScheduleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entryCount = snapshot.entries.length;
    final fetched = DateFormat('MM-dd HH:mm').format(snapshot.fetchedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageH,
        AppSpacing.sm,
        AppSpacing.pageH,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.term.name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BigStat(
                value: '${snapshot.courses.length}',
                label: '门课程',
              ),
              const SizedBox(width: AppSpacing.xl),
              _BigStat(
                value: '$entryCount',
                label: '节次',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '上次同步 $fetched',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = warn ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

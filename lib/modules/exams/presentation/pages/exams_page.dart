import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../domain/entities/exam_schedule_snapshot.dart';
import '../controllers/exams_controller.dart';

class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('考试安排')),
      body: ConstrainedBody(
        child: AsyncValueView(
          value: examsAsync,
          onRetry: () => ref.read(examsControllerProvider.notifier).refresh(),
          loadingLabel: '考试安排同步中',
          dataBuilder: (snapshot) => RefreshIndicator(
            onRefresh: () =>
                ref.read(examsControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _ExamsHero(
                  snapshot: snapshot,
                  onSwitchTerm: snapshot.availableTerms.isNotEmpty
                      ? () => _showTermPicker(snapshot)
                      : null,
                ),
                const SizedBox(height: 16),
                if (snapshot.records.isEmpty)
                  _EmptyExamsState()
                else
                  for (final record in snapshot.records) ...[
                    _ExamCard(record: record, onTap: () => _openDetail(record)),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(ExamRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ExamDetailSheet(record: record),
    );
  }

  Future<void> _showTermPicker(ExamScheduleSnapshot snapshot) async {
    final selectedTermId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '切换学期',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '从学期列表中选择要查看的考试安排。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF607172),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: snapshot.availableTerms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final term = snapshot.availableTerms[index];
                      final isSelected = term.id == snapshot.term.id;
                      return Material(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).pop(term.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    term.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                else
                                  const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted ||
        selectedTermId == null ||
        selectedTermId == snapshot.term.id) {
      return;
    }

    final success = await ref
        .read(examsControllerProvider.notifier)
        .changeTerm(selectedTermId);
    if (!mounted) {
      return;
    }
    if (!success) {
      AppSnackBar.show(
        context,
        message: '该学期考试安排加载失败，已恢复到之前的学期',
        tone: AppSnackBarTone.error,
      );
    }
  }
}

class _ExamsHero extends StatelessWidget {
  const _ExamsHero({required this.snapshot, this.onSwitchTerm});

  final ExamScheduleSnapshot snapshot;
  final VoidCallback? onSwitchTerm;

  @override
  Widget build(BuildContext context) {
    final syncLabel = DateFormat(
      'MM-dd HH:mm',
    ).format(snapshot.fetchedAt.toLocal());

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4A34), Color(0xFF5A3D3D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x227C4A34),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        snapshot.term.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    if (onSwitchTerm != null)
                      Material(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: onSwitchTerm,
                          borderRadius: BorderRadius.circular(16),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '共 ${snapshot.records.length} 条考试记录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '最近同步 $syncLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.record, required this.onTap});

  final ExamRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      record.courseName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(record.dateLabel),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(record.timeLabel),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(record.location)),
                ],
              ),
              if (record.displayMetaTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in record.displayMetaTags)
                      _ExamMetaTag(label: label),
                  ],
                ),
              ],
              if (record.seatNumber != null &&
                  record.seatNumber!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.chair_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text('座位号：${record.seatNumber}'),
                  ],
                ),
              ],
              if (record.remark != null && record.remark!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(record.remark!)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamMetaTag extends StatelessWidget {
  const _ExamMetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ExamDetailSheet extends StatelessWidget {
  const _ExamDetailSheet({required this.record});

  final ExamRecord record;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.courseName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${record.dateLabel} · ${record.timeLabel}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ExamMetaTag(label: record.location),
                  for (final label in record.displayMetaTags)
                    _ExamMetaTag(label: label),
                  if (record.seatNumber != null &&
                      record.seatNumber!.isNotEmpty)
                    _ExamMetaTag(label: '座位 ${record.seatNumber}'),
                ],
              ),
              const SizedBox(height: 20),
              _ExamDetailBlock(
                title: '课程编号',
                value: record.courseCode ?? '未提供',
                icon: Icons.confirmation_number_outlined,
              ),
              const SizedBox(height: 12),
              _ExamDetailBlock(
                title: '班级',
                value: record.className ?? '未提供',
                icon: Icons.groups_2_outlined,
              ),
              const SizedBox(height: 12),
              _ExamDetailBlock(
                title: '主讲教师',
                value: record.primaryTeacher ?? '未提供',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 12),
              _ExamDetailBlock(
                title: '辅讲教师',
                value: record.assistantTeacher ?? '未提供',
                icon: Icons.people_outline_rounded,
              ),
              const SizedBox(height: 12),
              _ExamDetailBlock(
                title: '参考人数',
                value: record.candidateCount == null
                    ? '未提供'
                    : '${record.candidateCount} 人',
                icon: Icons.groups_outlined,
              ),
              const SizedBox(height: 12),
              _ExamDetailBlock(
                title: '备注',
                value: record.remark ?? '未提供',
                icon: Icons.notes_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamDetailBlock extends StatelessWidget {
  const _ExamDetailBlock({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExamsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF7C4A34).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: Color(0xFF7C4A34),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '暂无考试安排',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '当前没有查询到考试安排。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF607172)),
          ),
        ],
      ),
    );
  }
}

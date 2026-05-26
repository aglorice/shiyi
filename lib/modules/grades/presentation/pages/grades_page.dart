import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../schedule/domain/entities/schedule_snapshot.dart';
import '../../domain/entities/grades_snapshot.dart';
import '../controllers/grades_controller.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  @override
  Widget build(BuildContext context) {
    final gradesAsync = ref.watch(gradesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('成绩查询')),
      body: ConstrainedBody(
        child: AsyncValueView(
          value: gradesAsync,
          onRetry: () => ref.read(gradesControllerProvider.notifier).refresh(),
          loadingLabel: '成绩同步中',
          dataBuilder: (snapshot) {
            final selectedTerm = snapshot.selectedTerm;
            final visibleRecords = snapshot.records;
            final visibleSections = selectedTerm == null
                ? snapshot.terms
                : [selectedTerm.name];

            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(gradesControllerProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _GradesHero(
                    snapshot: snapshot,
                    selectedTerm: selectedTerm,
                    visibleRecords: visibleRecords,
                    onPickTerm: () => _showTermPicker(snapshot),
                  ),
                  const SizedBox(height: 16),
                  _TermFilterBar(
                    terms: snapshot.filterTerms,
                    selectedTermId: selectedTerm?.id ?? '',
                    onSelected: (termId) {
                      _changeTerm(termId);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (visibleRecords.isEmpty)
                    _EmptyTermState(
                      termName: selectedTerm?.name ?? '全部学期',
                      isAllTerms: selectedTerm == null,
                    )
                  else
                    for (final sectionTitle in visibleSections) ...[
                      _GradeTermSection(
                        termName: sectionTitle,
                        records: selectedTerm == null
                            ? snapshot.recordsForTerm(sectionTitle)
                            : visibleRecords,
                        onOpenDetail: _openDetail,
                      ),
                      if (sectionTitle != visibleSections.last)
                        const SizedBox(height: 16),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showTermPicker(GradesSnapshot snapshot) async {
    final selected = await showModalBottomSheet<String>(
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
                  '选择学期',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  '这里优先使用教务学期列表，再兼容成绩数据里的实际学期标签。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: snapshot.filterTerms.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final term = index == 0
                          ? null
                          : snapshot.filterTerms[index - 1];
                      final label = term?.name ?? '全部学期';
                      final isSelected = term == null
                          ? snapshot.selectedTerm == null
                          : term.id == snapshot.selectedTerm?.id;

                      return Material(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () =>
                              Navigator.of(context).pop(term?.id ?? ''),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.chevron_right_rounded,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
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

    if (!mounted) {
      return;
    }

    if (selected == null) {
      return;
    }
    await _changeTerm(selected);
  }

  Future<void> _openDetail(GradeRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _GradeDetailSheet(record: record),
    );
  }

  Future<void> _changeTerm(String termId) async {
    final success = await ref
        .read(gradesControllerProvider.notifier)
        .changeTerm(termId);
    if (!mounted || success) {
      return;
    }
    AppSnackBar.show(
      context,
      message: '该学期成绩加载失败，已恢复到之前的学期',
      tone: AppSnackBarTone.error,
    );
  }
}

class _GradesHero extends StatelessWidget {
  const _GradesHero({
    required this.snapshot,
    required this.selectedTerm,
    required this.visibleRecords,
    required this.onPickTerm,
  });

  final GradesSnapshot snapshot;
  final Term? selectedTerm;
  final List<GradeRecord> visibleRecords;
  final VoidCallback onPickTerm;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = selectedTerm?.name ?? '全部学期';

    return SurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '成绩总览',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$selectedLabel · ${visibleRecords.length} 条记录',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '最近同步：${DateFormat('MM-dd HH:mm').format(snapshot.fetchedAt.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onPickTerm,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('选择学期'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(
                Icons.school_outlined,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TermFilterBar extends StatelessWidget {
  const _TermFilterBar({
    required this.terms,
    required this.selectedTermId,
    required this.onSelected,
  });

  final List<Term> terms;
  final String selectedTermId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: selectedTermId.isEmpty,
              onSelected: (_) => onSelected(''),
            ),
          ),
          for (final term in terms)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(term.name),
                selected: selectedTermId == term.id,
                onSelected: (_) => onSelected(term.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _GradeTermSection extends StatelessWidget {
  const _GradeTermSection({
    required this.termName,
    required this.records,
    required this.onOpenDetail,
  });

  final String termName;
  final List<GradeRecord> records;
  final ValueChanged<GradeRecord> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  termName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${records.length} 门',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final record in records) ...[
            _GradeRecordCard(record: record, onTap: () => onOpenDetail(record)),
            if (record != records.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _EmptyTermState extends StatelessWidget {
  const _EmptyTermState({required this.termName, required this.isAllTerms});

  final String termName;
  final bool isAllTerms;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.school_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isAllTerms ? '暂无成绩' : '$termName 暂无成绩',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            isAllTerms
                ? '当前没有可展示的成绩记录，可以稍后刷新重试。'
                : '这个学期目前没有可展示的成绩记录，可以切回全部学期查看。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeRecordCard extends StatelessWidget {
  const _GradeRecordCard({required this.record, required this.onTap});

  final GradeRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.courseName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (record.courseCode != null) record.courseCode,
                        if (record.teacher != null) record.teacher,
                        if (record.assessmentMethod != null)
                          record.assessmentMethod,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (record.credit != null)
                          _GradeTag(label: '${record.credit} 学分'),
                        if (record.gradePoint != null)
                          _GradeTag(label: '绩点 ${record.gradePoint}'),
                        if (record.classHours != null)
                          _GradeTag(label: '${record.classHours} 学时'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    record.grade,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeTag extends StatelessWidget {
  const _GradeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GradeDetailSheet extends StatelessWidget {
  const _GradeDetailSheet({required this.record});

  final GradeRecord record;

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
                '${record.termName} · ${record.grade}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailTag(label: record.termName),
                  if (record.assessmentMethod != null)
                    _DetailTag(label: record.assessmentMethod!),
                  if (record.credit != null)
                    _DetailTag(label: '${record.credit} 学分'),
                  if (record.gradePoint != null)
                    _DetailTag(label: '绩点 ${record.gradePoint}'),
                ],
              ),
              const SizedBox(height: 20),
              _DetailBlock(
                title: '课程编号',
                value: record.courseCode ?? '未提供',
                icon: Icons.confirmation_number_outlined,
              ),
              const SizedBox(height: 12),
              _DetailBlock(
                title: '任课老师',
                value: record.teacher ?? '未提供',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 12),
              _DetailBlock(
                title: '学时',
                value: record.classHours == null
                    ? '未提供'
                    : '${record.classHours} 学时',
                icon: Icons.schedule_rounded,
              ),
              const SizedBox(height: 12),
              _DetailBlock(
                title: '考核方式',
                value: record.assessmentMethod ?? '未提供',
                icon: Icons.fact_check_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailTag extends StatelessWidget {
  const _DetailTag({required this.label});

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

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
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

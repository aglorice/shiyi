import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/gym_appointment_page.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../../domain/entities/gym_search_filter.dart';
import '../controllers/gym_booking_controller.dart';
import '../widgets/gym_booking_components.dart';

class GymMyAppointmentsPage extends ConsumerStatefulWidget {
  const GymMyAppointmentsPage({super.key});

  @override
  ConsumerState<GymMyAppointmentsPage> createState() =>
      _GymMyAppointmentsPageState();
}

class _GymMyAppointmentsPageState extends ConsumerState<GymMyAppointmentsPage> {
  /// 远端代码表拉不到时的兜底（覆盖学校 SYZT.do 已知的 3 个值）。
  static const _fallbackStatusOptions = <(String, String?)>[
    ('全部', null),
    ('未使用', '001'),
    ('已使用', '002'),
    ('已取消', '003'),
  ];

  late final TextEditingController _keywordController;
  String? _selectedStatusCode;
  GymAppointmentPage? _page;
  Object? _error;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch(reset: true);
    });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool reset}) async {
    if (_loading || _loadingMore) return;

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    final authState = await ref.read(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '当前未登录，无法加载预约记录。';
      });
      return;
    }

    final query = GymAppointmentQuery(
      pageNumber: reset ? 1 : (_page?.query.pageNumber ?? 1) + 1,
      pageSize: 20,
      keyword: _keywordController.text.trim(),
      statusCode: _selectedStatusCode,
    );

    final result = await ref.read(fetchGymAppointmentsPageUseCaseProvider)(
      session: session,
      query: query,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case Success<GymAppointmentPage>(data: final data):
        setState(() {
          final merged = reset || _page == null
              ? data.records
              : [..._page!.records, ...data.records];
          _page = data.copyWith(records: _deduplicateAndSort(merged));
          _loading = false;
          _loadingMore = false;
        });
      case FailureResult<GymAppointmentPage>(failure: final failure):
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = failure;
        });
    }
  }

  /// 按 [BookingRecord.dedupeKey]（即 `ID_` 主键）去重。
  /// 旧实现按 `WID` 去重会把同场地多次预约错杀，这里换成稳定主键。
  /// 排序：先按预约日期降序（最新在前），同日期再按申请时间降序。
  List<BookingRecord> _deduplicateAndSort(List<BookingRecord> records) {
    final seen = <String>{};
    final unique = <BookingRecord>[];
    for (final record in records) {
      if (seen.add(record.dedupeKey)) {
        unique.add(record);
      }
    }
    unique.sort((a, b) {
      final dateCompare = b.date.compareTo(a.date);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final left = a.submittedAt;
      final right = b.submittedAt;
      if (left != null && right != null) {
        return right.compareTo(left);
      }
      return 0;
    });
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('我的预约')),
      body: ConstrainedBody(
        child: RefreshIndicator(
          onRefresh: () => _fetch(reset: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
            children: [
              SurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '搜索与筛选',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keywordController,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: '搜索场地名称',
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: '输入场地名称后回车',
                      ),
                      onSubmitted: (_) => _fetch(reset: true),
                    ),
                    const SizedBox(height: 12),
                    _StatusFilterChips(
                      selectedCode: _selectedStatusCode,
                      fallback: _fallbackStatusOptions,
                      onChanged: (code) {
                        setState(() => _selectedStatusCode = code);
                        _fetch(reset: true);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _keywordController.clear();
                              setState(() => _selectedStatusCode = null);
                              _fetch(reset: true);
                            },
                            child: const Text('清空条件'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _fetch(reset: true),
                            child: const Text('重新查询'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_page != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '已加载 ${_page!.records.length} 条，远程总数 ${_page!.totalSize}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_loadingMore)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_loading && _page == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _page == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      formatError(_error!).message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else if (_page != null && _page!.records.isEmpty)
                SurfaceCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_busy_rounded,
                          size: 38,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '没有匹配的预约记录',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                if (_page!.records.isNotEmpty)
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 14,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _page!.records.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 0.6,
                              thickness: 0.6,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.55),
                            ),
                          GymAppointmentTile(
                            record: _page!.records[i],
                            onTap: () => context.push(
                              '/gym-booking/appointment/${_page!.records[i].id}',
                              extra: _page!.records[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formatError(_error!).message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_page?.hasMore == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.tonal(
                      onPressed: _loadingMore
                          ? null
                          : () => _fetch(reset: false),
                      child: Text(_loadingMore ? '加载中...' : '加载更多'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// SYZT 状态筛选 chip：
/// - 优先用 `gymAppointmentSearchModelProvider` 拉到的 SYZT 控件 + 其
///   `gymCodeOptionsProvider` 候选项；
/// - 拉不到时回落到本地常量 [fallback]，UI 永远可用。
/// "全部"始终显示在最前面。
class _StatusFilterChips extends ConsumerWidget {
  const _StatusFilterChips({
    required this.selectedCode,
    required this.fallback,
    required this.onChanged,
  });

  final String? selectedCode;
  final List<(String, String?)> fallback;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelAsync = ref.watch(gymAppointmentSearchModelProvider);
    final options = modelAsync.maybeWhen(
      data: (model) => _buildFromModel(ref, model),
      orElse: () => null,
    );

    final entries = options ?? fallback;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: entries.map((item) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(item.$1),
              selected: selectedCode == item.$2,
              onSelected: (_) => onChanged(item.$2),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 从远端 model 里取 SYZT 控件，再去 [gymCodeOptionsProvider] 拿候选项。
  /// 候选项已通过 `ref.watch` 触发的 family provider 缓存，多次重建不重复请求。
  List<(String, String?)>? _buildFromModel(WidgetRef ref, GymSearchModel model) {
    final control = model.controlByName('SYZT');
    final url = control?.url;
    if (url == null || url.isEmpty) {
      return null;
    }
    final optionsAsync = ref.watch(gymCodeOptionsProvider(url));
    final options = optionsAsync.value;
    if (options == null || options.isEmpty) {
      return null;
    }
    return [
      ('全部', null),
      for (final option in options) (option.label, option.id),
    ];
  }
}

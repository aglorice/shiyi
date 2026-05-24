import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../../domain/entities/gym_search_filter.dart';
import '../controllers/gym_booking_controller.dart';
import '../widgets/gym_booking_components.dart';
import '../widgets/phone_number_dialog.dart';

class GymBookingProfilePage extends ConsumerWidget {
  const GymBookingProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final searchModelAsync = ref.watch(gymSearchModelProvider);
    final appointmentsAsync = ref.watch(myGymAppointmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('预约偏好')),
      body: ConstrainedBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
          children: [
            _ProfileInfoCard(preferences: preferences),
            const SizedBox(height: 14),
            _PreferenceCard(
              preferences: preferences,
              searchModelAsync: searchModelAsync,
            ),
            const SizedBox(height: 14),
            _ProfileAppointmentsCard(appointmentsAsync: appointmentsAsync),
          ],
        ),
      ),
    );
  }
}

class _ProfileInfoCard extends ConsumerWidget {
  const _ProfileInfoCard({required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final phone = preferences.gymPhoneNumber;

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '预约信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _editPhone(context, ref),
                icon: const Icon(Icons.phone_android_rounded),
                label: Text(phone?.isNotEmpty == true ? '修改手机号' : '设置手机号'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            phone?.isNotEmpty == true ? phone! : '尚未设置',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: phone?.isNotEmpty == true
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPhone(BuildContext context, WidgetRef ref) async {
    final phone = await showPhoneNumberDialog(context);
    if (phone == null || !context.mounted) {
      return;
    }
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .setGymPhoneNumber(phone);
    if (!context.mounted) {
      return;
    }
    AppSnackBar.show(
      context,
      message: '预约手机号已更新',
      tone: AppSnackBarTone.success,
      icon: Icons.phone_android_rounded,
    );
  }
}

class _PreferenceCard extends ConsumerWidget {
  const _PreferenceCard({
    required this.preferences,
    required this.searchModelAsync,
  });

  final AppPreferences preferences;
  final AsyncValue<GymSearchModel> searchModelAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '推荐偏好',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '设置后，主页面的”为你推荐”将按偏好筛选。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          switch (searchModelAsync) {
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OptionSelector(
                  title: '偏好运动',
                  selectedId: preferences.gymPreferredSportId,
                  options: value.sports,
                  onChanged: (option) async {
                    if (option == null) {
                      await ref
                          .read(appPreferencesControllerProvider.notifier)
                          .clearGymPreferredSport();
                      return;
                    }
                    await ref
                        .read(appPreferencesControllerProvider.notifier)
                        .setGymPreferredSport(
                          id: option.id,
                          label: option.label,
                        );
                  },
                ),
                const SizedBox(height: 14),
                _OptionSelector(
                  title: '偏好场馆',
                  selectedId: preferences.gymPreferredVenueTypeId,
                  options: value.venueTypes,
                  onChanged: (option) async {
                    if (option == null) {
                      await ref
                          .read(appPreferencesControllerProvider.notifier)
                          .clearGymPreferredVenueType();
                      return;
                    }
                    await ref
                        .read(appPreferencesControllerProvider.notifier)
                        .setGymPreferredVenueType(
                          id: option.id,
                          label: option.label,
                        );
                  },
                ),
              ],
            ),
            AsyncError(:final error) => Text(
              formatError(error).message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          },
          const SizedBox(height: 14),
          Text(
            '偏好时段',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('不限'),
                selected: preferences.gymTimePreference == null,
                onSelected: (_) {
                  ref
                      .read(appPreferencesControllerProvider.notifier)
                      .clearGymTimePreference();
                },
              ),
              ...GymTimePreference.values.map((item) {
                return ChoiceChip(
                  label: Text(item.label),
                  selected: preferences.gymTimePreference == item,
                  onSelected: (_) {
                    ref
                        .read(appPreferencesControllerProvider.notifier)
                        .setGymTimePreference(item);
                  },
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionSelector extends StatelessWidget {
  const _OptionSelector({
    required this.title,
    required this.selectedId,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String? selectedId;
  final List<GymFilterOption> options;
  final ValueChanged<GymFilterOption?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('不限'),
              selected: selectedId == null,
              onSelected: (_) => onChanged(null),
            ),
            ...options.map((option) {
              final isSelected = option.id == selectedId;
              return ChoiceChip(
                label: Text(option.label),
                selected: isSelected,
                onSelected: (_) => onChanged(isSelected ? null : option),
              );
            }),
          ],
        ),
      ],
    );
  }
}

class _ProfileAppointmentsCard extends StatelessWidget {
  const _ProfileAppointmentsCard({required this.appointmentsAsync});

  final AsyncValue<List<BookingRecord>> appointmentsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的预约',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/gym-booking/my'),
                child: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          switch (appointmentsAsync) {
            AsyncData(:final value) =>
              value.isEmpty
                  ? Text(
                      '还没有预约记录。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      children: value.take(4).map((record) {
                        final visible = value.take(4).toList();
                        return Column(
                          children: [
                            GymAppointmentTile(
                              record: record,
                              onTap: () => context.push(
                                '/gym-booking/appointment/${record.id}',
                                extra: record,
                              ),
                            ),
                            if (record != visible.last)
                              const Divider(height: 20),
                          ],
                        );
                      }).toList(),
                    ),
            AsyncError(:final error) => Text(
              formatError(error).message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
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

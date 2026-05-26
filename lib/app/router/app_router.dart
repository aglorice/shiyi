import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../di/app_providers.dart';
import '../settings/app_preferences_controller.dart';
import '../../modules/auth/presentation/controllers/auth_controller.dart';
import '../../modules/auth/presentation/pages/login_page.dart';
import '../../modules/electricity/presentation/pages/electricity_page.dart';
import '../../modules/exams/presentation/pages/exams_page.dart';
import '../../modules/grades/presentation/pages/grades_page.dart';
import '../../modules/gym_booking/domain/entities/gym_booking_overview.dart';
import '../../modules/gym_booking/presentation/pages/gym_appointment_detail_page.dart';
import '../../modules/gym_booking/presentation/pages/gym_booking_page.dart';
import '../../modules/gym_booking/presentation/pages/gym_booking_profile_page.dart';
import '../../modules/gym_booking/presentation/pages/gym_my_appointments_page.dart';
import '../../modules/gym_booking/presentation/pages/gym_venue_detail_page.dart';
import '../../modules/gym_booking/presentation/pages/gym_venue_search_page.dart';
import '../../modules/home/presentation/pages/home_page.dart';
import '../../modules/notices/domain/entities/campus_notice.dart';
import '../../modules/notices/presentation/pages/notice_detail_page.dart';
import '../../modules/notices/presentation/pages/notices_page.dart';
import '../../modules/onboarding/presentation/pages/onboarding_page.dart';
import '../../modules/personal_info/presentation/pages/app_access_logs_page.dart';
import '../../modules/personal_info/presentation/pages/auth_logs_page.dart';
import '../../modules/personal_info/presentation/pages/online_sessions_page.dart';
import '../../modules/personal_info/presentation/pages/password_logs_page.dart';
import '../../modules/personal_info/presentation/pages/personal_info_page.dart';
import '../../modules/profile/presentation/pages/about_app_page.dart';
import '../../modules/profile/presentation/pages/profile_page.dart';
import '../../modules/profile/presentation/pages/settings_appearance_page.dart';
import '../../modules/profile/presentation/pages/settings_github_mirror_page.dart';
import '../../modules/profile/presentation/pages/settings_logs_page.dart';
import '../../modules/profile/presentation/pages/settings_schedule_export_page.dart';
import '../../modules/profile/presentation/pages/settings_schedule_page.dart';
import '../../modules/profile/presentation/pages/settings_storage_page.dart';
import '../../modules/schedule/presentation/pages/schedule_page.dart';
import '../../modules/school_news/domain/entities/school_news.dart';
import '../../modules/school_news/presentation/pages/school_news_detail_page.dart';
import '../../modules/school_news/presentation/pages/school_news_page.dart';
import '../../modules/services/domain/entities/service_card_data.dart';
import '../../modules/services/presentation/pages/service_webview_page.dart';
import '../../modules/services/presentation/pages/services_page.dart';
import '../../shared/pages/link_webview_page.dart';
import '../shell/campus_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // 用一个稳定的 notifier 触发 GoRouter 的 redirect 重新评估，
  // 而不是 ref.watch(authControllerProvider) —— 后者每次 auth state 变化
  // 都会重建整个 GoRouter，从而把 LoginPage 卸载掉，导致登录中弹出的
  // 滑块 sheet 因 BuildContext 失效而无法显示。
  final refreshListenable = ValueNotifier<int>(0);
  final logger = ref.watch(appLoggerProvider);
  ref.listen(authControllerProvider, (prev, next) {
    refreshListenable.value++;
    final prevAuth = prev?.value?.isAuthenticated ?? false;
    final nextAuth = next.value?.isAuthenticated ?? false;
    final status = next.value?.status.name ?? 'loading';
    logger.info('[ROUTER] auth changed status=$status '
        'isAuth=$prevAuth → $nextAuth, refresh router');
  });
  // onboarding 完成后也要触发 redirect 重新评估，否则用户点完"开始使用"
  // 仍然停在 /onboarding。
  ref.listen<bool>(
    appPreferencesControllerProvider
        .select((p) => p.onboardingCompleted),
    (_, __) => refreshListenable.value++,
  );
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    refreshListenable: refreshListenable,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return CampusShell(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: buildCampusShellNavigatorContainer,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (context, state) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedule',
                builder: (context, state) => const SchedulePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notices',
                builder: (context, state) => const NoticesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/grades', builder: (context, state) => const GradesPage()),
      GoRoute(path: '/exams', builder: (context, state) => const ExamsPage()),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutAppPage(),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (context, state) => const SettingsAppearancePage(),
      ),
      GoRoute(
        path: '/settings/schedule',
        builder: (context, state) => const SettingsSchedulePage(),
      ),
      GoRoute(
        path: '/settings/gym',
        builder: (context, state) => const GymBookingProfilePage(),
      ),
      GoRoute(
        path: '/settings/storage',
        builder: (context, state) => const SettingsStoragePage(),
      ),
      GoRoute(
        path: '/settings/github-mirror',
        builder: (context, state) => const SettingsGithubMirrorPage(),
      ),
      GoRoute(
        path: '/settings/schedule-export',
        builder: (context, state) => const SettingsScheduleExportPage(),
      ),
      GoRoute(
        path: '/settings/logs',
        builder: (context, state) => const SettingsLogsPage(),
      ),
      GoRoute(
        path: '/personal-info',
        builder: (context, state) => const PersonalInfoPage(),
      ),
      GoRoute(
        path: '/personal-info/online',
        builder: (context, state) => const OnlineSessionsPage(),
      ),
      GoRoute(
        path: '/personal-info/auth-logs',
        builder: (context, state) => const AuthLogsPage(),
      ),
      GoRoute(
        path: '/personal-info/app-logs',
        builder: (context, state) => const AppAccessLogsPage(),
      ),
      GoRoute(
        path: '/personal-info/password-logs',
        builder: (context, state) => const PasswordLogsPage(),
      ),
      GoRoute(
        path: '/browser',
        builder: (context, state) {
          final title = state.uri.queryParameters['title'] ?? '链接';
          final urlText = state.uri.queryParameters['url'];
          final uri = urlText == null ? null : Uri.tryParse(urlText);
          if (uri == null || !uri.hasScheme) {
            return const Scaffold(body: Center(child: Text('链接参数缺失')));
          }
          return LinkWebViewPage(title: title, uri: uri);
        },
      ),
      GoRoute(
        path: '/electricity',
        builder: (context, state) => const ElectricityPage(),
      ),
      GoRoute(
        path: '/gym-booking',
        builder: (context, state) => const GymBookingPage(),
      ),
      GoRoute(
        path: '/gym-booking/profile',
        builder: (context, state) => const GymBookingProfilePage(),
      ),
      GoRoute(
        path: '/gym-booking/search',
        builder: (context, state) {
          final dateText = state.uri.queryParameters['date'];
          final initialDate = dateText == null
              ? null
              : DateTime.tryParse(dateText);
          return GymVenueSearchPage(initialDate: initialDate);
        },
      ),
      GoRoute(
        path: '/gym-booking/my',
        builder: (context, state) => const GymMyAppointmentsPage(),
      ),
      GoRoute(
        path: '/gym-booking/appointment/:wid',
        builder: (context, state) {
          final wid = state.pathParameters['wid'] ?? '';
          final prefillRecord = state.extra is BookingRecord
              ? state.extra as BookingRecord
              : null;
          return GymAppointmentDetailPage(
            appointmentId: wid,
            prefillRecord: prefillRecord,
          );
        },
      ),
      GoRoute(
        path: '/gym-booking/venue/:wid',
        builder: (context, state) {
          final wid = state.pathParameters['wid'] ?? '';
          final name = state.uri.queryParameters['name'] ?? '场地详情';
          final bizWid = state.uri.queryParameters['bizWid'];
          final dateText = state.uri.queryParameters['date'];
          final initialDate = dateText == null
              ? null
              : DateTime.tryParse(dateText);
          return GymVenueDetailPage(
            venueId: wid,
            venueName: name,
            bizWid: bizWid,
            initialDate: initialDate,
          );
        },
      ),
      GoRoute(
        path: '/services',
        builder: (context, state) => const ServicesPage(),
      ),
      GoRoute(
        path: '/services/webview',
        builder: (context, state) {
          final item = state.extra;
          if (item is! ServiceItem) {
            return const Scaffold(body: Center(child: Text('服务参数缺失')));
          }
          return ServiceWebViewPage(item: item);
        },
      ),
      GoRoute(
        path: '/notices/detail',
        builder: (context, state) {
          final item = state.extra;
          if (item is! CampusNoticeItem) {
            return const Scaffold(body: Center(child: Text('通知参数缺失')));
          }
          return NoticeDetailPage(item: item);
        },
      ),
      GoRoute(
        path: '/school-news',
        builder: (context, state) => const SchoolNewsPage(),
      ),
      GoRoute(
        path: '/school-news/detail',
        builder: (context, state) {
          final item = state.extra;
          if (item is! SchoolNewsItem) {
            return const Scaffold(body: Center(child: Text('要闻参数缺失')));
          }
          return SchoolNewsDetailPage(item: item);
        },
      ),
    ],
    redirect: (context, state) {
      final authAsync = ref.read(authControllerProvider);
      final preferences = ref.read(appPreferencesControllerProvider);
      final loc = state.matchedLocation;
      final isLogin = loc == '/login';
      final isOnboarding = loc == '/onboarding';
      final isAuthenticated = authAsync.value?.isAuthenticated ?? false;
      final isPublicNoticeRoute =
          state.matchedLocation == '/notices' ||
          state.matchedLocation == '/notices/detail';
      final isPublicSchoolNewsRoute =
          state.matchedLocation == '/school-news' ||
          state.matchedLocation == '/school-news/detail';

      if (authAsync.isLoading) {
        return null;
      }

      // 首次启动：还没看过引导 → 先把人引到 /onboarding。
      // 已认证用户也照样要看一遍（升级到带引导的版本时让用户重温一次新功能）。
      if (!preferences.onboardingCompleted && !isOnboarding) {
        return '/onboarding';
      }

      if (preferences.onboardingCompleted && isOnboarding) {
        return isAuthenticated ? '/' : '/login';
      }

      if (!isAuthenticated &&
          !isLogin &&
          !isOnboarding &&
          !isPublicNoticeRoute &&
          !isPublicSchoolNewsRoute) {
        return '/login';
      }

      if (isAuthenticated && isLogin) {
        return '/';
      }

      return null;
    },
  );
});

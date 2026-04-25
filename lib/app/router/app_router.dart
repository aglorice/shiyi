import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../modules/profile/presentation/pages/about_app_page.dart';
import '../../modules/profile/presentation/pages/profile_page.dart';
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
  final authAsync = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/',
    routes: [
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
      final isLogin = state.matchedLocation == '/login';
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

      if (!isAuthenticated &&
          !isLogin &&
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

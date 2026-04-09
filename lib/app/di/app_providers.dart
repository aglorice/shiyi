import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/user_agent_pool.dart';
import '../../core/platform/app_installer_service.dart';
import '../../core/platform/downloads_service.dart';
import '../../core/platform/file_save_service.dart';
import '../../core/storage/json_cache_store.dart';
import '../../core/storage/shared_preferences_json_store.dart';
import '../../integrations/app_update/github_release_api.dart';
import '../../integrations/campus_notices/wyu_notice_api.dart';
import '../../integrations/electricity_recharge/wyu_electricity_api.dart';
import '../../integrations/electricity_recharge/wyu_electricity_parser.dart';
import '../../integrations/school_portal/school_portal_gateway.dart';
import '../../integrations/school_portal/sso/credential_transformer.dart';
import '../../integrations/school_portal/sso/session_validator.dart';
import '../../integrations/school_portal/sso/sso_login_orchestrator.dart';
import '../../integrations/school_portal/wyu_portal_api.dart';
import '../../modules/auth/application/login_with_school_portal_use_case.dart';
import '../../modules/auth/application/logout_use_case.dart';
import '../../modules/auth/application/refresh_session_use_case.dart';
import '../../modules/auth/application/restore_session_use_case.dart';
import '../../modules/auth/data/auth_repository_impl.dart';
import '../../modules/auth/data/credential_vault.dart';
import '../../modules/auth/data/session_store.dart';
import '../../modules/auth/domain/repositories/auth_repository.dart';
import '../../modules/electricity/application/fetch_electricity_dashboard_use_case.dart';
import '../../modules/electricity/data/electricity_repository_impl.dart';
import '../../modules/electricity/domain/repositories/electricity_repository.dart';
import '../../modules/exams/application/fetch_exam_schedule_use_case.dart';
import '../../modules/exams/data/exams_repository_impl.dart';
import '../../modules/exams/domain/repositories/exams_repository.dart';
import '../../modules/grades/application/fetch_grades_use_case.dart';
import '../../modules/grades/data/grades_repository_impl.dart';
import '../../modules/grades/domain/repositories/grades_repository.dart';
import '../../modules/gym_booking/application/cancel_gym_appointment_use_case.dart';
import '../../modules/gym_booking/application/fetch_appointment_detail_use_case.dart';
import '../../modules/gym_booking/application/fetch_gym_appointments_page_use_case.dart';
import '../../modules/gym_booking/application/fetch_gym_booking_overview_use_case.dart';
import '../../modules/gym_booking/application/fetch_gym_search_model_use_case.dart';
import '../../modules/gym_booking/application/fetch_my_gym_appointments_use_case.dart';
import '../../modules/gym_booking/application/fetch_venue_detail_use_case.dart';
import '../../modules/gym_booking/application/fetch_venue_reviews_use_case.dart';
import '../../modules/gym_booking/application/search_gym_venues_use_case.dart';
import '../../modules/gym_booking/application/submit_gym_booking_use_case.dart';
import '../../modules/gym_booking/data/gym_booking_repository_impl.dart';
import '../../modules/gym_booking/domain/repositories/gym_booking_repository.dart';
import '../../modules/notices/application/fetch_notice_detail_use_case.dart';
import '../../modules/notices/application/fetch_notice_category_page_use_case.dart';
import '../../modules/notices/application/fetch_notices_use_case.dart';
import '../../modules/notices/data/notices_repository_impl.dart';
import '../../modules/notices/domain/repositories/notices_repository.dart';
import '../../modules/schedule/application/fetch_schedule_use_case.dart';
import '../../modules/schedule/data/schedule_repository_impl.dart';
import '../../modules/schedule/domain/repositories/schedule_repository.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences must be bootstrapped.'),
);

final appLoggerProvider = Provider<AppLogger>((ref) => const AppLogger());

final downloadsServiceProvider = Provider<DownloadsService>(
  (ref) => const DownloadsService(),
);

final appInstallerServiceProvider = Provider<AppInstallerService>(
  (ref) => const AppInstallerService(),
);

final fileSaveServiceProvider = Provider<FileSaveService>(
  (ref) => FileSaveService(ref.watch(downloadsServiceProvider)),
);

final gitHubReleaseApiProvider = Provider<GitHubReleaseApi>(
  (ref) => GitHubReleaseApi(logger: ref.watch(appLoggerProvider)),
);

final jsonCacheStoreProvider = Provider<JsonCacheStore>(
  (ref) => SharedPreferencesJsonStore(ref.watch(sharedPreferencesProvider)),
);

final credentialVaultProvider = Provider<CredentialVault>(
  (ref) => SecureCredentialVault(const FlutterSecureStorage()),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SharedPreferencesSessionStore(ref.watch(sharedPreferencesProvider)),
);

final credentialTransformerProvider = Provider<CredentialTransformer>(
  (ref) => CredentialTransformer(),
);

final userAgentPoolProvider = Provider<UserAgentPool>(
  (ref) => UserAgentPool(ref.watch(sharedPreferencesProvider)),
);

final wyuPortalApiProvider = Provider<WyuPortalApi>(
  (ref) => WyuPortalApi(
    transformer: ref.watch(credentialTransformerProvider),
    logger: ref.watch(appLoggerProvider),
    userAgent: ref.watch(userAgentPoolProvider).get(),
  ),
);

final ssoLoginOrchestratorProvider = Provider<SsoLoginOrchestrator>(
  (ref) => SsoLoginOrchestrator(portalApi: ref.watch(wyuPortalApiProvider)),
);

final sessionValidatorProvider = Provider<SessionValidator>(
  (ref) => SessionValidator(portalApi: ref.watch(wyuPortalApiProvider)),
);

final schoolPortalGatewayProvider = Provider<SchoolPortalGateway>(
  (ref) => WyuSchoolPortalGateway(
    loginOrchestrator: ref.watch(ssoLoginOrchestratorProvider),
    sessionValidator: ref.watch(sessionValidatorProvider),
    portalApi: ref.watch(wyuPortalApiProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    gateway: ref.watch(schoolPortalGatewayProvider),
    credentialVault: ref.watch(credentialVaultProvider),
    sessionStore: ref.watch(sessionStoreProvider),
  ),
);

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => ScheduleRepositoryImpl(
    gateway: ref.watch(schoolPortalGatewayProvider),
    cacheStore: ref.watch(jsonCacheStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final gradesRepositoryProvider = Provider<GradesRepository>(
  (ref) => GradesRepositoryImpl(
    gateway: ref.watch(schoolPortalGatewayProvider),
    cacheStore: ref.watch(jsonCacheStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final examsRepositoryProvider = Provider<ExamsRepository>(
  (ref) => ExamsRepositoryImpl(
    gateway: ref.watch(schoolPortalGatewayProvider),
    cacheStore: ref.watch(jsonCacheStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final wyuElectricityParserProvider = Provider<WyuElectricityParser>(
  (ref) => const WyuElectricityParser(),
);

final wyuElectricityApiProvider = Provider<WyuElectricityApi>(
  (ref) => WyuElectricityApi(
    parser: ref.watch(wyuElectricityParserProvider),
    logger: ref.watch(appLoggerProvider),
    userAgent: ref.watch(userAgentPoolProvider).get(),
  ),
);

final electricityRepositoryProvider = Provider<ElectricityRepository>(
  (ref) => ElectricityRepositoryImpl(
    api: ref.watch(wyuElectricityApiProvider),
    cacheStore: ref.watch(jsonCacheStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final gymBookingRepositoryProvider = Provider<GymBookingRepository>(
  (ref) => GymBookingRepositoryImpl(
    gateway: ref.watch(schoolPortalGatewayProvider),
    cacheStore: ref.watch(jsonCacheStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final wyuNoticeApiProvider = Provider<WyuNoticeApi>(
  (ref) => WyuNoticeApi(
    logger: ref.watch(appLoggerProvider),
    userAgent: ref.watch(userAgentPoolProvider).get(),
  ),
);

final noticesRepositoryProvider = Provider<NoticesRepository>(
  (ref) => NoticesRepositoryImpl(
    api: ref.watch(wyuNoticeApiProvider),
    cacheStore: ref.watch(jsonCacheStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final loginWithSchoolPortalUseCaseProvider =
    Provider<LoginWithSchoolPortalUseCase>(
      (ref) => LoginWithSchoolPortalUseCase(ref.watch(authRepositoryProvider)),
    );

final refreshSessionUseCaseProvider = Provider<RefreshSessionUseCase>(
  (ref) => RefreshSessionUseCase(ref.watch(authRepositoryProvider)),
);

final restoreSessionUseCaseProvider = Provider<RestoreSessionUseCase>(
  (ref) => RestoreSessionUseCase(ref.watch(authRepositoryProvider)),
);

final logoutUseCaseProvider = Provider<LogoutUseCase>(
  (ref) => LogoutUseCase(ref.watch(authRepositoryProvider)),
);

final fetchScheduleUseCaseProvider = Provider<FetchScheduleUseCase>(
  (ref) => FetchScheduleUseCase(ref.watch(scheduleRepositoryProvider)),
);

final fetchGradesUseCaseProvider = Provider<FetchGradesUseCase>(
  (ref) => FetchGradesUseCase(ref.watch(gradesRepositoryProvider)),
);

final fetchExamScheduleUseCaseProvider = Provider<FetchExamScheduleUseCase>(
  (ref) => FetchExamScheduleUseCase(ref.watch(examsRepositoryProvider)),
);

final fetchElectricityDashboardUseCaseProvider =
    Provider<FetchElectricityDashboardUseCase>(
      (ref) => FetchElectricityDashboardUseCase(
        ref.watch(electricityRepositoryProvider),
      ),
    );

final fetchGymBookingOverviewUseCaseProvider =
    Provider<FetchGymBookingOverviewUseCase>(
      (ref) => FetchGymBookingOverviewUseCase(
        ref.watch(gymBookingRepositoryProvider),
      ),
    );

final submitGymBookingUseCaseProvider = Provider<SubmitGymBookingUseCase>(
  (ref) => SubmitGymBookingUseCase(ref.watch(gymBookingRepositoryProvider)),
);

final fetchMyGymAppointmentsUseCaseProvider =
    Provider<FetchMyGymAppointmentsUseCase>(
      (ref) => FetchMyGymAppointmentsUseCase(
        ref.watch(gymBookingRepositoryProvider),
      ),
    );

final fetchGymAppointmentsPageUseCaseProvider =
    Provider<FetchGymAppointmentsPageUseCase>(
      (ref) => FetchGymAppointmentsPageUseCase(
        ref.watch(gymBookingRepositoryProvider),
      ),
    );

final searchGymVenuesUseCaseProvider = Provider<SearchGymVenuesUseCase>(
  (ref) => SearchGymVenuesUseCase(ref.watch(gymBookingRepositoryProvider)),
);

final fetchNoticesUseCaseProvider = Provider<FetchNoticesUseCase>(
  (ref) => FetchNoticesUseCase(ref.watch(noticesRepositoryProvider)),
);

final fetchNoticeCategoryPageUseCaseProvider =
    Provider<FetchNoticeCategoryPageUseCase>(
      (ref) =>
          FetchNoticeCategoryPageUseCase(ref.watch(noticesRepositoryProvider)),
    );

final fetchNoticeDetailUseCaseProvider = Provider<FetchNoticeDetailUseCase>(
  (ref) => FetchNoticeDetailUseCase(ref.watch(noticesRepositoryProvider)),
);

final fetchAppointmentDetailUseCaseProvider =
    Provider<FetchAppointmentDetailUseCase>(
      (ref) => FetchAppointmentDetailUseCase(
        ref.watch(gymBookingRepositoryProvider),
      ),
    );

final cancelGymAppointmentUseCaseProvider =
    Provider<CancelGymAppointmentUseCase>(
      (ref) =>
          CancelGymAppointmentUseCase(ref.watch(gymBookingRepositoryProvider)),
    );

final fetchVenueDetailUseCaseProvider = Provider<FetchVenueDetailUseCase>(
  (ref) => FetchVenueDetailUseCase(ref.watch(gymBookingRepositoryProvider)),
);

final fetchVenueReviewsUseCaseProvider = Provider<FetchVenueReviewsUseCase>(
  (ref) => FetchVenueReviewsUseCase(ref.watch(gymBookingRepositoryProvider)),
);

final fetchGymSearchModelUseCaseProvider = Provider<FetchGymSearchModelUseCase>(
  (ref) => FetchGymSearchModelUseCase(ref.watch(gymBookingRepositoryProvider)),
);

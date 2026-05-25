// 这个 library 把 WyuSchoolPortalGateway 按子领域拆成多个 part 文件，
// 避免单文件 4000+ 行。
//
// 共享状态（_loginOrchestrator / _sessionValidator / _portalApi / _logger
// / _random）放在 [_GatewayBase]，每个子领域作为一个 mixin 通过
// `on _GatewayBase implements SchoolPortalGateway` 把若干 @override 方法挂上来。
//
// 拆分原则：
// - _base.dart            — 共享字段 + 跨领域 JSON / 日期 / 学期助手
// - _auth.dart            — login / refreshSession / validateSession / logout
// - _personal_info.dart   — 用户日志 / 在线 / 踢出 / IP 查询
// - _sms_login.dart       — 短信登录代理
// - _schedule.dart        — 课表（本科 + 研究生 + 网格解析）
// - _grades.dart          — 成绩（本科 + 研究生）
// - _exams.dart           — 考试安排（本科 + 研究生）
// - _electricity.dart     — 电费占位
// - _gym.dart             — 体育馆预约：概览/搜索/我的预约/详情/评论/搜索模型/code 候选项
// - _services.dart        — 校园服务卡片 + 单点登录跳转

import 'dart:convert';
import 'dart:math';

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/data_origin.dart';
import '../../core/result/result.dart';
import '../../modules/auth/domain/entities/app_session.dart';
import '../../modules/auth/domain/entities/school_credential.dart';
import '../../modules/electricity/domain/entities/electricity_dashboard.dart';
import '../../modules/exams/domain/entities/exam_schedule_snapshot.dart';
import '../../modules/grades/domain/entities/grades_snapshot.dart';
import '../../modules/gym_booking/domain/entities/appointment_detail.dart';
import '../../modules/gym_booking/domain/entities/gym_appointment_page.dart';
import '../../modules/gym_booking/domain/entities/gym_booking_overview.dart';
import '../../modules/gym_booking/domain/entities/gym_search_filter.dart';
import '../../modules/gym_booking/domain/entities/gym_venue_search_page.dart';
import '../../modules/gym_booking/domain/entities/venue_detail.dart';
import '../../modules/gym_booking/domain/entities/venue_review.dart';
import '../../modules/personal_info/domain/entities/user_log_entry.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';
import '../../modules/services/domain/entities/service_card_data.dart';
import '../../modules/services/domain/entities/service_launch_data.dart';
import 'sso/session_validator.dart';
import 'sso/slider_captcha.dart';
import 'sso/sms_login_session.dart';
import 'sso/sso_login_orchestrator.dart';
import 'wyu_portal_api.dart';

part 'school_portal_gateway/_base.dart';
part 'school_portal_gateway/_auth.dart';
part 'school_portal_gateway/_personal_info.dart';
part 'school_portal_gateway/_sms_login.dart';
part 'school_portal_gateway/_schedule.dart';
part 'school_portal_gateway/_grades.dart';
part 'school_portal_gateway/_exams.dart';
part 'school_portal_gateway/_electricity.dart';
part 'school_portal_gateway/_gym.dart';
part 'school_portal_gateway/_services.dart';

abstract class SchoolPortalGateway {
  /// 登录学号密码。
  /// [solveCaptcha] 在 needCaptcha=true 时被调用，由调用方负责弹滑块 sheet
  /// 并完成 verifySliderCaptcha；返回 true 表示通过。
  Future<Result<AppSession>> login(
    SchoolCredential credential, {
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  });
  Future<Result<AppSession>> refreshSession(SchoolCredential credential);
  Future<Result<void>> validateSession(AppSession session);

  /// 调用学校 SSO 注销接口，让远端 CASTGC 等会话 cookie 失效。
  /// 调用方仍然需要自行清本地 session/credential。
  Future<Result<void>> logout(AppSession session);

  // -------- 个人中心：访问/登录/密码 日志、当前在线 --------

  /// 拉一页用户日志（认证 / 密码 / 应用访问）。
  Future<Result<UserLogPage>> queryUserLogs(
    AppSession session, {
    required UserLogType type,
    int pageIndex = 1,
    int pageSize = 10,
  });

  /// 拉当前在线会话列表。
  Future<Result<List<OnlineSession>>> queryOnlineSessions(AppSession session);

  /// 踢出某个在线会话。可能踢的是当前 session（参见 [KickOnlineResult.selfKicked]）。
  Future<KickOnlineResult> kickOnlineSession(
    AppSession session, {
    required String id,
  });

  /// IP 归属地查询。返回 null 视为未知。
  Future<String?> lookupIpLocation(String ip);

  /// 启动短信登录流程，拿到一个用于贯穿后续滑块/发短信/登录三步的 [SmsLoginSession]。
  Future<Result<SmsLoginSession>> startSmsLogin();

  /// 拉取一张滑块挑战图（可重复调用以换图）。
  Future<Result<SliderCaptchaChallenge>> openSliderCaptcha(
    SmsLoginSession smsSession,
  );

  /// 提交滑动轨迹做校验。errorCode == 1 即通过。
  Future<Result<SliderVerifyResult>> verifySliderCaptcha(
    SmsLoginSession smsSession, {
    required SliderTrackPayload payload,
    required String safeSecure,
  });

  /// 滑块通过后向服务端发送短信。返回成功提示语 / 失败原因。
  Future<Result<String>> sendDynamicCode(
    SmsLoginSession smsSession, {
    required String mobile,
  });

  /// 用收到的 6 位短信验证码完成登录，返回完整 [AppSession]。
  Future<Result<AppSession>> submitSmsLogin(
    SmsLoginSession smsSession, {
    required String mobile,
    required String dynamicCode,
  });
  Future<Result<ScheduleSnapshot>> fetchSchedule(
    AppSession session, {
    String? termId,
  });
  Future<Result<GradesSnapshot>> fetchGrades(
    AppSession session, {
    String? termId,
  });
  Future<Result<ExamScheduleSnapshot>> fetchExamSchedule(
    AppSession session, {
    String? termId,
  });
  Future<Result<ElectricityDashboard>> fetchElectricityDashboard(
    AppSession session,
  );
  Future<Result<GymBookingOverview>> fetchGymBookingOverview(
    AppSession session, {
    required DateTime date,
  });
  Future<Result<BookingRecord>> submitGymBooking(
    AppSession session, {
    required BookingDraft draft,
  });
  Future<Result<GymBookingEligibility>> checkGymBookingEligibility(
    AppSession session, {
    required BookingDraft draft,
  });
  Future<Result<List<BookingRecord>>> fetchMyGymAppointments(
    AppSession session, {
    int page = 1,
    int pageSize = 20,
  });
  Future<Result<GymAppointmentPage>> fetchMyGymAppointmentsPage(
    AppSession session, {
    required GymAppointmentQuery query,
  });

  Future<Result<GymVenueSearchPage>> searchGymVenues(
    AppSession session, {
    required GymVenueSearchQuery query,
  });

  Future<Result<AppointmentDetail>> fetchGymAppointmentDetail(
    AppSession session, {
    required String wid,
  });

  Future<Result<void>> cancelGymAppointment(
    AppSession session, {
    required String appointmentId,
    String? reason,
  });

  Future<Result<VenueDetail>> fetchGymRoomDetail(
    AppSession session, {
    required String wid,
  });

  Future<Result<VenueReviewPage>> fetchGymRoomReviews(
    AppSession session, {
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  });

  Future<Result<GymSearchModel>> fetchGymSearchModel(AppSession session);

  /// 拉"我的预约"列表的 searchMeta，返回里包含 SYZT/HYSLX/SFWY 等控件
  /// 及它们对应的 code URL，调用方用它去 [fetchGymCodeOptions] 拿候选项。
  Future<Result<GymSearchModel>> fetchGymAppointmentSearchModel(
    AppSession session,
  );

  /// 灵活拉取任意一个 `/qljfwapp/code/<id>.do` 候选项。
  /// 内部缓存 + POST/GET 双探测，调用方只需要给 url。
  Future<Result<List<GymFilterOption>>> fetchGymCodeOptions(
    AppSession session, {
    required String codeUrl,
  });

  /// 查询场地在某天"实时剩余可约"的时段列表。
  /// 后端会在这里剔除已被订走/被锁定的时段，所以这是比 `getOpeningRoom.do`
  /// 的 `day1..day7.times` 更准确的可约时段来源。
  Future<Result<List<String>>> fetchGymRoomAvailableSlots(
    AppSession session, {
    required String roomId,
    required DateTime applyDate,
  });
  Future<Result<List<ServiceCardGroup>>> fetchServiceCards(AppSession session);
  Future<Result<List<ServiceItem>>> fetchServiceCategoryItems(
    AppSession session, {
    required String cardWid,
    required ServiceCategory category,
  });
  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  });
}

/// 五邑学校门户网关的真实实现。
///
/// 类本身只承担"装配"职责：通过 mixin 链把 [_GatewayBase] 与各子领域 mixin
/// 组合成完整的 [SchoolPortalGateway]。具体业务方法都散落在 part 文件里。
class WyuSchoolPortalGateway extends _GatewayBase
    with
        _AuthGateway,
        _PersonalInfoGateway,
        _SmsLoginGateway,
        _ScheduleGateway,
        _GradesGateway,
        _ExamsGateway,
        _ElectricityGateway,
        _GymGateway,
        _ServicesGateway
    implements SchoolPortalGateway {
  WyuSchoolPortalGateway({
    required super.loginOrchestrator,
    required super.sessionValidator,
    required super.portalApi,
    required super.logger,
  });
}

// -------------------- 课表解析中间态（part 共用） --------------------

class _ParsedScheduleSession {
  const _ParsedScheduleSession({
    required this.courseId,
    required this.courseName,
    required this.teacher,
    required this.courseCode,
    required this.note,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.weekRange,
    required this.location,
    required this.startSection,
    required this.endSection,
    required this.weekDescription,
    required this.dayLabel,
  });

  final String courseId;
  final String courseName;
  final String teacher;
  final String? courseCode;
  final String? note;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final WeekRange weekRange;
  final TeachingLocation location;
  final int? startSection;
  final int? endSection;
  final String? weekDescription;
  final String? dayLabel;
}

class _MutableParsedScheduleSession {
  _MutableParsedScheduleSession({
    required this.courseId,
    required this.courseName,
    required this.teacher,
    required this.courseCode,
    required this.note,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.weekRange,
    required this.location,
    required this.startSection,
    required this.endSection,
    required this.weekDescription,
    required this.dayLabel,
  });

  final String courseId;
  final String courseName;
  final String teacher;
  final String? courseCode;
  final String? note;
  final int dayOfWeek;
  String startTime;
  String endTime;
  final WeekRange weekRange;
  final TeachingLocation location;
  final int startSection;
  int endSection;
  final String? weekDescription;
  final String? dayLabel;

  _ParsedScheduleSession toImmutable() {
    return _ParsedScheduleSession(
      courseId: courseId,
      courseName: courseName,
      teacher: teacher,
      courseCode: courseCode,
      note: note,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      endTime: endTime,
      weekRange: weekRange,
      location: location,
      startSection: startSection,
      endSection: endSection,
      weekDescription: weekDescription,
      dayLabel: dayLabel,
    );
  }
}

class _ParsedYjsGridCellCourse {
  const _ParsedYjsGridCellCourse({
    required this.courseName,
    required this.teacher,
    required this.location,
    required this.weekRange,
    required this.weekDescription,
    required this.note,
  });

  final String courseName;
  final String teacher;
  final TeachingLocation location;
  final WeekRange weekRange;
  final String weekDescription;
  final String? note;
}

// -------------------- 测试桩 --------------------

class TestingSchoolPortalGateway implements SchoolPortalGateway {
  const TestingSchoolPortalGateway();

  @override
  Future<Result<List<ServiceCardGroup>>> fetchServiceCards(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入校园服务。'));
  }

  @override
  Future<Result<List<ServiceItem>>> fetchServiceCategoryItems(
    AppSession session, {
    required String cardWid,
    required ServiceCategory category,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入校园服务分类。'));
  }

  @override
  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  }) async {
    final url =
        item.launchCandidates.isNotEmpty ? item.launchCandidates.first : '';
    if (url.isEmpty) {
      return const FailureResult(BusinessFailure('测试环境未接入服务跳转。'));
    }
    return Success(
      ServiceLaunchData(
        initialUrl: url,
        resolvedUrl: url,
        cookies: session.cookies,
      ),
    );
  }

  @override
  Future<Result<ElectricityDashboard>> fetchElectricityDashboard(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入电费。'));
  }

  @override
  Future<Result<ExamScheduleSnapshot>> fetchExamSchedule(
    AppSession session, {
    String? termId,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入考试安排。'));
  }

  @override
  Future<Result<GradesSnapshot>> fetchGrades(
    AppSession session, {
    String? termId,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入成绩查询。'));
  }

  @override
  Future<Result<GymBookingOverview>> fetchGymBookingOverview(
    AppSession session, {
    required DateTime date,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<ScheduleSnapshot>> fetchSchedule(
    AppSession session, {
    String? termId,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入课表查询。'));
  }

  @override
  Future<Result<AppSession>> login(
    SchoolCredential credential, {
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  }) async {
    return Success(
      AppSession(
        userId: credential.username,
        displayName: credential.username,
        cookies: const [
          PortalCookie(
            name: 'CASTGC',
            value: 'testing',
            domain: 'authserver.wyu.edu.cn',
          ),
        ],
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
        profile: PortalUserProfile(
          userName: credential.username,
          userAccount: credential.username,
        ),
      ),
    );
  }

  @override
  Future<Result<AppSession>> refreshSession(SchoolCredential credential) {
    return login(credential);
  }

  @override
  Future<Result<BookingRecord>> submitGymBooking(
    AppSession session, {
    required BookingDraft draft,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<GymBookingEligibility>> checkGymBookingEligibility(
    AppSession session, {
    required BookingDraft draft,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入预约校验。'));
  }

  @override
  Future<Result<List<BookingRecord>>> fetchMyGymAppointments(
    AppSession session, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<GymAppointmentPage>> fetchMyGymAppointmentsPage(
    AppSession session, {
    required GymAppointmentQuery query,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<GymVenueSearchPage>> searchGymVenues(
    AppSession session, {
    required GymVenueSearchQuery query,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<AppointmentDetail>> fetchGymAppointmentDetail(
    AppSession session, {
    required String wid,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入预约详情。'));
  }

  @override
  Future<Result<void>> cancelGymAppointment(
    AppSession session, {
    required String appointmentId,
    String? reason,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入取消预约。'));
  }

  @override
  Future<Result<VenueDetail>> fetchGymRoomDetail(
    AppSession session, {
    required String wid,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入场地详情。'));
  }

  @override
  Future<Result<VenueReviewPage>> fetchGymRoomReviews(
    AppSession session, {
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入场地评论。'));
  }

  @override
  Future<Result<GymSearchModel>> fetchGymSearchModel(AppSession session) async {
    return const FailureResult(BusinessFailure('测试环境未接入搜索模型。'));
  }

  @override
  Future<Result<GymSearchModel>> fetchGymAppointmentSearchModel(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入预约搜索模型。'));
  }

  @override
  Future<Result<List<GymFilterOption>>> fetchGymCodeOptions(
    AppSession session, {
    required String codeUrl,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入代码表查询。'));
  }

  @override
  Future<Result<List<String>>> fetchGymRoomAvailableSlots(
    AppSession session, {
    required String roomId,
    required DateTime applyDate,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入实时时段查询。'));
  }

  @override
  Future<Result<void>> validateSession(AppSession session) async {
    return const Success(null);
  }

  @override
  Future<Result<void>> logout(AppSession session) async {
    return const Success(null);
  }

  @override
  Future<Result<UserLogPage>> queryUserLogs(
    AppSession session, {
    required UserLogType type,
    int pageIndex = 1,
    int pageSize = 10,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入访问记录。'));
  }

  @override
  Future<Result<List<OnlineSession>>> queryOnlineSessions(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入在线会话。'));
  }

  @override
  Future<KickOnlineResult> kickOnlineSession(
    AppSession session, {
    required String id,
  }) async {
    return KickOnlineResult.error;
  }

  @override
  Future<String?> lookupIpLocation(String ip) async => null;

  @override
  Future<Result<SmsLoginSession>> startSmsLogin() async {
    return const FailureResult(BusinessFailure('测试环境未接入短信登录。'));
  }

  @override
  Future<Result<SliderCaptchaChallenge>> openSliderCaptcha(
    SmsLoginSession smsSession,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入短信登录。'));
  }

  @override
  Future<Result<SliderVerifyResult>> verifySliderCaptcha(
    SmsLoginSession smsSession, {
    required SliderTrackPayload payload,
    required String safeSecure,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入短信登录。'));
  }

  @override
  Future<Result<String>> sendDynamicCode(
    SmsLoginSession smsSession, {
    required String mobile,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入短信登录。'));
  }

  @override
  Future<Result<AppSession>> submitSmsLogin(
    SmsLoginSession smsSession, {
    required String mobile,
    required String dynamicCode,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入短信登录。'));
  }
}

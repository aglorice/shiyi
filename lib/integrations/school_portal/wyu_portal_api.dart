// 这个 library 把"五邑统一身份认证 + ehall + 子系统接入"按子领域拆成
// 多个 part 文件，避免单文件 2000+ 行难以维护。
//
// 各 part 之间共享类内字段（_dio、_runtimeStates、_logger 等），
// 私有助手类型 (_CookieStore、_TransportResponse、_RuntimeState、_LoginFormData)
// 仅在 library 内可见。
//
// 拆分原则：
// - _internal.dart        — Cookie / 重定向 / 日志 / 通用解析助手
// - _auth.dart            — 学号密码登录、注销、session 校验、登录页解析
// - _sms_login.dart       — 短信验证码登录全流程
// - _personal_info.dart   — 个人中心：日志、在线、踢出、IP 查询
// - _services.dart        — 门户服务列表 / 单点登录 / 服务卡片
// - _gym.dart             — 体育馆预约 (qljfwapp)
// - _jxgl.dart            — 本科生教务系统
// - _yjs.dart             — 研究生教务系统

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../core/error/failure.dart';
import '../../core/logging/api_log_interceptor.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/auth/domain/entities/app_session.dart';
import '../../modules/auth/domain/entities/school_credential.dart';
import '../../modules/personal_info/domain/entities/user_log_entry.dart';
import '../../modules/services/domain/entities/service_card_data.dart';
import '../../modules/services/domain/entities/service_launch_data.dart';
import 'sso/credential_transformer.dart';
import 'sso/slider_captcha.dart';
import 'sso/sms_login_session.dart';

part 'wyu_portal_api/_internal.dart';
part 'wyu_portal_api/_auth.dart';
part 'wyu_portal_api/_sms_login.dart';
part 'wyu_portal_api/_personal_info.dart';
part 'wyu_portal_api/_services.dart';
part 'wyu_portal_api/_gym.dart';
part 'wyu_portal_api/_jxgl.dart';
part 'wyu_portal_api/_yjs.dart';

/// 五邑大学统一身份认证 + ehall + 各子系统的对外门面类。
///
/// 这个类本身只承载共享状态：Dio 实例、运行时 cookieStore 缓存、logger 等；
/// 真正的业务方法分散在同 library 的 part 文件中作为 extension 实现。
class WyuPortalApi {
  WyuPortalApi({
    required CredentialTransformer transformer,
    required AppLogger logger,
    required String userAgent,
  }) : _transformer = transformer,
       _logger = logger,
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 20),
           receiveTimeout: const Duration(seconds: 20),
           followRedirects: false,
           maxRedirects: 0,
           responseType: ResponseType.plain,
           validateStatus: (_) => true,
           headers: {'User-Agent': userAgent},
         ),
       )..interceptors.add(ApiLogInterceptor(label: 'Portal'));

  final CredentialTransformer _transformer;
  final AppLogger _logger;
  final Dio _dio;
  final Random _random = Random();
  final Map<String, _RuntimeState> _runtimeStates = {};

  /// 已经 warmup 过 personalInfo 的 cookieStore 缓存。
  /// runtimeStates 复用 cookieStore 实例时，这里也命中。
  final Set<_CookieStore> _personalInfoReady = <_CookieStore>{};
}

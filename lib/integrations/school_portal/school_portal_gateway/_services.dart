// 校园服务 / 系统直通车卡片，以及单点登录跳转。
part of '../school_portal_gateway.dart';

mixin _ServicesGateway on _GatewayBase implements SchoolPortalGateway {
  static const _serviceCardWid = '8558486040491173';
  static const _yjsServiceCardWid = '017434820995445355';

  @override
  Future<Result<List<ServiceCardGroup>>> fetchServiceCards(
    AppSession session,
  ) async {
    _logger.info('[Gateway] 开始加载服务卡片 userId=${session.userId}');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 服务卡片加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    final groups = <ServiceCardGroup>[];

    final serviceCardResult = await _portalApi.fetchServiceCardData(
      session,
      _serviceCardWid,
    );
    if (serviceCardResult case Success<Map<String, dynamic>>(
      data: final data,
    )) {
      final group = _parseServiceCardGroup('校园服务', _serviceCardWid, data);
      if (group != null) {
        groups.add(group);
      }
    } else {
      _logger.warn('[Gateway] 校园服务卡片加载失败');
    }

    final yjsCardResult = await _portalApi.fetchServiceCardData(
      session,
      _yjsServiceCardWid,
    );
    if (yjsCardResult case Success<Map<String, dynamic>>(data: final data)) {
      final group = _parseServiceCardGroup('系统直通车', _yjsServiceCardWid, data);
      if (group != null) {
        groups.add(group);
      }
    } else {
      _logger.warn('[Gateway] 系统直通车卡片加载失败');
    }

    if (groups.isEmpty) {
      return const FailureResult(ParsingFailure('未加载到任何服务数据。'));
    }

    _logger.info(
      '[Gateway] 服务卡片加载完成 groupCount=${groups.length} '
      'totalItems=${groups.fold<int>(0, (sum, g) => sum + g.items.length)}',
    );
    return Success(groups);
  }

  @override
  Future<Result<List<ServiceItem>>> fetchServiceCategoryItems(
    AppSession session, {
    required String cardWid,
    required ServiceCategory category,
  }) async {
    _logger.info(
      '[Gateway] 开始加载服务分类 cardWid=$cardWid typeId=${category.typeId} typeName=${category.typeName}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 服务分类加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchServiceCardData(
      session,
      cardWid,
      typeId: category.typeId,
    );
    if (result case FailureResult<Map<String, dynamic>>(
      failure: final failure,
    )) {
      return FailureResult(failure);
    }

    final parsed = _parseServiceCardGroup(
      '分类服务',
      cardWid,
      result.requireValue(),
    );
    if (parsed == null) {
      return const FailureResult(ParsingFailure('服务分类解析失败。'));
    }

    final items = parsed.itemsForCategory(category);
    if (items.isNotEmpty) {
      return Success(items);
    }

    return Success(parsed.items);
  }

  @override
  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  }) async {
    _logger.info(
      '[Gateway] 准备进入服务 app=${item.appName} userId=${session.userId}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 服务跳转前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    return _portalApi.prepareServiceLaunch(session, item: item);
  }

  // -------------------- 服务卡片解析 --------------------

  ServiceCardGroup? _parseServiceCardGroup(
    String cardName,
    String cardWid,
    Map<String, dynamic> raw,
  ) {
    final data = raw['data'];
    if (data is! Map<String, dynamic>) return null;

    final categories = _parseServiceCategories(data);
    final items = _parseServiceItems(data);
    if (items.isEmpty && categories.isEmpty) return null;

    // If classifyData was empty, fall back to deriving categories from items
    if (categories.isEmpty && items.isNotEmpty) {
      final categoryMap = <String, ServiceCategory>{};
      final countMap = <String, int>{};
      for (final item in items) {
        countMap[item.typeId] = (countMap[item.typeId] ?? 0) + 1;
        if (!categoryMap.containsKey(item.typeId)) {
          categoryMap[item.typeId] = ServiceCategory(
            typeId: item.typeId,
            typeName: item.typeId.isEmpty ? '其他' : item.typeId,
            count: countMap[item.typeId]!,
          );
        } else {
          categoryMap[item.typeId] = categoryMap[item.typeId]!.copyWith(
            count: countMap[item.typeId],
          );
        }
      }
      categories.addAll(categoryMap.values);
    }

    return ServiceCardGroup(
      cardWid: cardWid,
      cardName: cardName,
      categories: categories,
      items: items,
    );
  }

  List<ServiceCategory> _parseServiceCategories(Map<String, dynamic> data) {
    final categories = <ServiceCategory>[];
    final classifyData = data['classifyData'];
    if (classifyData is! List) {
      return categories;
    }

    for (final cls in classifyData) {
      if (cls is! Map<String, dynamic>) continue;
      final show = cls['show'];
      if (show == false || show == 0) continue;
      final typeId = _pickString(cls, const ['typeId']);
      final typeName = _pickString(cls, const ['typeName']) ?? '其他';
      final count = _pickInt(cls, const ['count']) ?? 0;
      if (typeId != null && typeId.isNotEmpty) {
        categories.add(
          ServiceCategory(typeId: typeId, typeName: typeName, count: count),
        );
      }
    }

    return categories;
  }

  List<ServiceItem> _parseServiceItems(Map<String, dynamic> data) {
    final appData = data['appData'];
    if (appData is! List) {
      return const [];
    }

    final items = <ServiceItem>[];
    for (final svc in appData) {
      if (svc is! Map<String, dynamic>) continue;

      final appName = _pickString(svc, const [
        'appName',
        'serviceName',
        'name',
        'title',
      ]);
      if (appName == null || appName.isEmpty) continue;

      final appId =
          _pickString(svc, const ['appId', 'serviceId', 'wid', 'id']) ??
          appName;
      final iconLink = _pickString(svc, const [
        'iconLink',
        'icon',
        'iconUrl',
        'img',
        'logo',
      ]);
      final pcAccessUrl = _pickString(svc, const [
        'pcAccessUrl',
        'url',
        'pcUrl',
      ]);
      final mobileAccessUrl = _pickString(svc, const [
        'mobileAccessUrl',
        'mobileUrl',
      ]);
      final wid = _pickString(svc, const ['wid', 'serviceWid', 'appWid']);

      final typeId =
          _pickString(svc, const [
            'typeId',
            'categoryId',
            'appTypeId',
            'classifyId',
            'classifyID',
            'typeID',
          ]) ??
          '';
      final typeName = _pickString(svc, const [
        'typeName',
        'categoryName',
        'appTypeName',
        'classifyName',
      ]);

      items.add(
        ServiceItem(
          appId: appId,
          appName: appName,
          iconLink: iconLink,
          pcAccessUrl: pcAccessUrl,
          mobileAccessUrl: mobileAccessUrl,
          wid: wid,
          typeId: typeId,
          typeName: typeName,
        ),
      );
    }

    return items;
  }
}

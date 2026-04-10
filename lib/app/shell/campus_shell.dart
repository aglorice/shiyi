import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/failure.dart';
import '../../modules/auth/presentation/controllers/auth_controller.dart';
import '../../modules/electricity/presentation/controllers/electricity_controller.dart';
import '../../modules/schedule/presentation/controllers/schedule_controller.dart';
import '../layout/breakpoints.dart';
import '../../shared/widgets/constrained_body.dart';
import '../../shared/widgets/session_expired_dialog.dart';

Widget buildCampusShellNavigatorContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= AppBreakpoints.desktop) {
    return _DesktopBranchNavigatorContainer(
      currentIndex: navigationShell.currentIndex,
      children: children,
    );
  }

  return _AnimatedBranchNavigatorContainer(
    currentIndex: navigationShell.currentIndex,
    children: children,
  );
}

class CampusShell extends ConsumerStatefulWidget {
  const CampusShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<CampusShell> createState() => _CampusShellState();
}

class _CampusShellState extends ConsumerState<CampusShell> {
  static const _railCollapsedWidth = 72.0;
  static const _railExpandedWidth = 196.0;
  static const _railHeaderReservedHeight = 68.0;
  static const _railToggleLeftOffset = 16.0;
  static const _railToggleBottomOffset = 20.0;

  bool _sessionDialogShown = false;
  bool _desktopRailExpanded = true;

  static const _destinations = [
    _CampusDestination(
      label: '总览',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    _CampusDestination(
      label: '课表',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today_rounded,
    ),
    _CampusDestination(
      label: '通知',
      icon: Icons.notifications_none_rounded,
      selectedIcon: Icons.notifications_rounded,
    ),
    _CampusDestination(
      label: '设置',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
    ),
  ];

  void _onSessionExpired() {
    if (_sessionDialogShown || !mounted) return;
    _sessionDialogShown = true;
    showSessionExpiredDialog(context, ref).whenComplete(() {
      _sessionDialogShown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scheduleControllerProvider, (_, next) {
      if (next.hasError && next.error is SessionExpiredFailure) {
        _onSessionExpired();
      }
    });
    ref.listen(electricityControllerProvider, (_, next) {
      if (next.hasError && next.error is SessionExpiredFailure) {
        _onSessionExpired();
      }
    });

    final authAsync = ref.watch(authControllerProvider);
    if (authAsync.isLoading) {
      return const Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= AppBreakpoints.rail;
    final isDesktop = width >= AppBreakpoints.desktop;
    final railExpanded = isDesktop && _desktopRailExpanded;

    if (useRail) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (isDesktop)
                _DesktopSidebar(
                  expanded: railExpanded,
                  selectedIndex: widget.navigationShell.currentIndex,
                  destinations: _destinations,
                  onDestinationSelected: (index) {
                    widget.navigationShell.goBranch(
                      index,
                      initialLocation:
                          index == widget.navigationShell.currentIndex,
                    );
                  },
                  onToggle: () {
                    setState(() {
                      _desktopRailExpanded = !_desktopRailExpanded;
                    });
                  },
                )
              else
                NavigationRail(
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: (index) {
                    widget.navigationShell.goBranch(
                      index,
                      initialLocation:
                          index == widget.navigationShell.currentIndex,
                    );
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: ConstrainedBody(child: widget.navigationShell)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: widget.navigationShell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) {
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          );
        },
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _CampusDestination {
  const _CampusDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.expanded,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.onToggle,
  });

  final bool expanded;
  final int selectedIndex;
  final List<_CampusDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final railTheme = theme.navigationRailTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: expanded
          ? _CampusShellState._railExpandedWidth
          : _CampusShellState._railCollapsedWidth,
      color: railTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 84),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                _DesktopRailHeader(expanded: expanded),
                const SizedBox(height: 6),
                for (var index = 0; index < destinations.length; index += 1)
                  _DesktopSidebarDestination(
                    expanded: expanded,
                    destination: destinations[index],
                    selected: selectedIndex == index,
                    onTap: () => onDestinationSelected(index),
                    indicatorColor:
                        railTheme.indicatorColor ??
                        colorScheme.primaryContainer.withValues(alpha: 0.72),
                  ),
              ],
            ),
          ),
          Positioned(
            left: _CampusShellState._railToggleLeftOffset,
            bottom: _CampusShellState._railToggleBottomOffset,
            child: _RailToggleButton(expanded: expanded, onPressed: onToggle),
          ),
        ],
      ),
    );
  }
}

class _DesktopRailHeader extends StatelessWidget {
  const _DesktopRailHeader({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _CampusShellState._railHeaderReservedHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/logo/pixel_cat_logo_1024.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            _RailAnimatedLabel(
              expanded: expanded,
              child: Text(
                '拾邑',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebarDestination extends StatelessWidget {
  const _DesktopSidebarDestination({
    required this.expanded,
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.indicatorColor,
  });

  final bool expanded;
  final _CampusDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final Color indicatorColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? indicatorColor : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                _RailAnimatedLabel(
                  expanded: expanded,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailAnimatedLabel extends StatelessWidget {
  const _RailAnimatedLabel({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: expanded ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            widthFactor: value,
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 12 * value),
              child: Opacity(opacity: value, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _RailToggleButton extends StatelessWidget {
  const _RailToggleButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shadowColor = colorScheme.shadow.withValues(alpha: 0.08);

    return Tooltip(
      message: expanded ? '收起导航' : '展开导航',
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              expanded
                  ? Icons.keyboard_double_arrow_left_rounded
                  : Icons.keyboard_double_arrow_right_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopBranchNavigatorContainer extends StatelessWidget {
  const _DesktopBranchNavigatorContainer({
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < children.length; index += 1)
            Offstage(
              offstage: index != currentIndex,
              child: TickerMode(
                enabled: index == currentIndex,
                child: RepaintBoundary(child: children[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedBranchNavigatorContainer extends StatefulWidget {
  const _AnimatedBranchNavigatorContainer({
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<_AnimatedBranchNavigatorContainer> createState() =>
      _AnimatedBranchNavigatorContainerState();
}

class _AnimatedBranchNavigatorContainerState
    extends State<_AnimatedBranchNavigatorContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..value = 1;

  late int _previousIndex = widget.currentIndex;

  @override
  void didUpdateWidget(covariant _AnimatedBranchNavigatorContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) {
      return;
    }

    _previousIndex = oldWidget.currentIndex;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;

          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var index = 0; index < widget.children.length; index += 1)
                  _buildBranch(
                    index: index,
                    child: widget.children[index],
                    progress: progress,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBranch({
    required int index,
    required Widget child,
    required double progress,
  }) {
    final isCurrent = index == widget.currentIndex;
    final isPrevious = _controller.isAnimating && index == _previousIndex;

    final outgoingProgress = Curves.easeOutCubic.transform(
      Interval(0, 0.35).transform(progress),
    );
    final incomingProgress = Curves.easeOutCubic.transform(
      Interval(0.22, 1).transform(progress),
    );

    final opacity = switch ((isCurrent, isPrevious, _controller.isAnimating)) {
      (true, _, true) => incomingProgress,
      (_, true, true) => 1 - outgoingProgress,
      (true, _, false) => 1.0,
      _ => 0.0,
    };

    final scale = switch ((isCurrent, isPrevious, _controller.isAnimating)) {
      (true, _, true) => 0.96 + 0.04 * incomingProgress,
      (_, true, true) => 1.0,
      _ => 1.0,
    };

    final isVisible = isCurrent || isPrevious;

    return Offstage(
      offstage: !isVisible,
      child: IgnorePointer(
        ignoring: !isCurrent,
        child: TickerMode(
          enabled: isCurrent || isPrevious,
          child: RepaintBoundary(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Opacity(opacity: opacity, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

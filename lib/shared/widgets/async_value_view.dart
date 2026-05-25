import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/error_display.dart';
import '../../core/error/failure.dart';
import 'module_error_state.dart';
import 'session_expired_dialog.dart';

class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.dataBuilder,
    this.onRetry,
    this.loadingLabel,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) dataBuilder;
  final VoidCallback? onRetry;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return switch (value) {
      AsyncData(:final value) => dataBuilder(value),
      AsyncError(:final error) => error is SessionExpiredFailure
          ? _SessionExpiredErrorView(message: error.message)
          : _GenericErrorView(error: error, onRetry: onRetry),
      _ => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (loadingLabel != null) ...[
                const SizedBox(height: 12),
                Text(loadingLabel!),
              ],
            ],
          ),
        ),
    };
  }
}

class _GenericErrorView extends StatelessWidget {
  const _GenericErrorView({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final info = formatError(error);
    return ModuleErrorState(
      message: info.message,
      icon: info.icon,
      failure: error is Failure ? error as Failure : null,
      onRetry: onRetry == null ? null : () async => onRetry!(),
    );
  }
}

class _SessionExpiredErrorView extends ConsumerStatefulWidget {
  const _SessionExpiredErrorView({required this.message});

  final String message;

  static bool _dialogActive = false;

  @override
  ConsumerState<_SessionExpiredErrorView> createState() =>
      _SessionExpiredErrorViewState();
}

class _SessionExpiredErrorViewState
    extends ConsumerState<_SessionExpiredErrorView> {
  @override
  void initState() {
    super.initState();
    _showDialog();
  }

  void _showDialog() {
    if (_SessionExpiredErrorView._dialogActive) return;
    _SessionExpiredErrorView._dialogActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _SessionExpiredErrorView._dialogActive = false;
        return;
      }
      showSessionExpiredDialog(context, ref).whenComplete(() {
        _SessionExpiredErrorView._dialogActive = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('登录已过期', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
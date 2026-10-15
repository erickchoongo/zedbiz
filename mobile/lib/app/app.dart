import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/app/theme.dart';
import 'package:zedbiz/features/auth/presentation/auth_screen.dart';
import 'package:zedbiz/features/businesses/presentation/business_list_screen.dart';
import 'package:zedbiz/features/businesses/presentation/business_ready_screen.dart';
import 'package:zedbiz/features/startup/presentation/splash_screen.dart';
import 'package:zedbiz/features/admin/presentation/admin_business_list_screen.dart';

class ZedBizApp extends StatefulWidget {
  const ZedBizApp({required this.controller, super.key});

  final AppController controller;

  @override
  State<ZedBizApp> createState() => _ZedBizAppState();
}

class _ZedBizAppState extends State<ZedBizApp> {
  final _navigator = GlobalKey<NavigatorState>();
  String? _scope;
  AppLifecycleListener? _lifecycle;
  void _contextChanged() {
    final c = widget.controller;
    final next =
        '${c.currentUser?.id}/${c.selectedBusiness?.id}/${c.selectedBusiness?.role}';
    if (_scope != null && _scope != next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _scope = next;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_contextChanged);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final c = widget.controller;
        if (c.selectedBusiness != null) {
          unawaited(c.offline?.syncPendingOperations(c.selectedBusiness!.id));
        }
      },
    );
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_contextChanged);
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'ZedBiz',
    debugShowCheckedModeBanner: false,
    theme: buildZedBizTheme(),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        return switch (controller.status) {
          SessionStatus.starting => const SplashScreen(),
          SessionStatus.signedOut => AuthScreen(controller: controller),
          SessionStatus.signedIn
              when controller.adminMode &&
                  controller.currentUser?.isPlatformAdmin == true =>
            AdminBusinessListScreen(controller: controller),
          SessionStatus.signedIn when controller.selectedBusiness != null =>
            BusinessReadyScreen(
              key: ValueKey(
                '${controller.currentUser?.id}/${controller.selectedBusiness?.id}/${controller.selectedBusiness?.role}',
              ),
              controller: controller,
            ),
          SessionStatus.signedIn => BusinessListScreen(controller: controller),
        };
      },
    ),
  );
}

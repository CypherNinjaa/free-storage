import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/auth.service.dart';
import 'package:logging/logging.dart';

/// Serverless Keepsake onboarding guard (Architecture §4 & §11 Phase 2).
/// Checks local onboarding completion without contacting any Immich server.
class AuthGuard extends AutoRouteGuard {
  final _log = Logger("AuthGuard");

  // Keep constructor signature compatible with AppRouter wiring.
  AuthGuard(ApiService _, AuthService _);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final token = Store.tryGet(StoreKey.accessToken);
    final user = Store.tryGet(StoreKey.currentUser);
    final vaultVersion = Store.tryGet(StoreKey.keepsakeVaultVersion);
    if (token == null || user == null || vaultVersion != 1) {
      _log.info('Keepsake onboarding not completed; redirecting to onboarding.');
      resolver.next(false);
      unawaited(router.replaceAll([const LoginRoute()]));
      return;
    }

    resolver.next(true);
  }
}

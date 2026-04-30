// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'presentation/router.dart';

/// Root [MaterialApp.router] for the POC.
///
/// Locale follows the device when supported; falls back to French (developer
/// walks in Melun, no English fallback chain needed beyond Material defaults).
/// Phase 1 ships the GoRouter from [appRouter] with three routes — gate, map
/// placeholder, denied — see `presentation/router.dart` for the route table.
///
/// Theme is intentionally minimal (Material 3 + indigo seed) — the deliverable
/// is the walk experience + the share-logs round-trip, not visual polish.
class MirkPocApp extends StatelessWidget {
  const MirkPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MirkFall POC',
      routerConfig: appRouter,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (Locale? locale, Iterable<Locale> supported) {
        if (locale != null && supported.any((Locale l) => l.languageCode == locale.languageCode)) {
          return locale;
        }
        // French fallback per CONTEXT.md — developer walks in Melun.
        return const Locale('fr');
      },
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      debugShowCheckedModeBanner: false,
    );
  }
}

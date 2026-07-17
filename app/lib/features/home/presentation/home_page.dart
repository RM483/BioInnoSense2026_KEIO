/// ホーム画面。犬の存在を主役に、それ以外は控えめに。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/h2.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../ble/data/ble_service.dart';
import '../../dogs/application/dog_controller.dart';
import '../../dogs/domain/dog.dart';
import '../../measurement/data/measurement_repository.dart';
import '../../measurement/domain/measurement.dart';

final _latestMeasurementProvider =
    StreamProvider.family<Measurement?, String>((ref, dogId) =>
        ref.watch(measurementRepositoryProvider).watchLatest(dogId));

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = ref.watch(selectedDogProvider);
    final connected =
        ref.watch(bleControllerProvider).status == BleStatus.connected;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            // ---- ヘッダ ----
            Row(
              children: [
                Expanded(
                  child: Text(l10n.appTitle,
                      style:
                          AppText.largeTitle.copyWith(color: p.textPrimary)),
                ),
                if (kUseMockBle) ...[
                  StatusPill(
                    label: l10n.demoMode,
                    color: p.accent,
                    softColor: p.accentSoft,
                    dot: false,
                  ),
                  const SizedBox(width: 8),
                ],
                _QuietIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: l10n.settings,
                  onTap: () => context.push(Routes.settings),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ---- 犬カード(主役) ----
            dog == null
                ? _EmptyDogCard(l10n: l10n)
                : _DogCard(dog: dog, l10n: l10n),
            const SizedBox(height: 14),

            // ---- 最新測定 ----
            if (dog != null)
              ref.watch(_latestMeasurementProvider(dog.id)).maybeWhen(
                    data: (m) =>
                        m == null ? const SizedBox.shrink() : _LatestCard(m),
                    orElse: () => const SizedBox.shrink(),
                  ),
            const SizedBox(height: 26),

            // ---- CTA ----
            FilledButton(
              onPressed: () =>
                  context.push(connected ? Routes.measure : Routes.connect),
              child:
                  Text(connected ? l10n.startMeasurement : l10n.bleConnect),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.push(Routes.history),
              child: Text(l10n.history),
            ),
          ],
        ),
      ),
    );
  }
}

class _DogCard extends ConsumerWidget {
  const _DogCard({required this.dog, required this.l10n});
  final Dog dog;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final details = [
      if (dog.breed.isNotEmpty) dog.breed,
      if (dog.ageYears != null) l10n.dogAgeYears(dog.ageYears!),
      if (dog.weightKg > 0) '${dog.weightKg}kg',
    ].join('  ·  ');

    return AppCard(
      onTap: () => context.push(Routes.dog),
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          _DogAvatar(photoUrl: dog.photoUrl, size: 84),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dog.name,
                    style: AppText.title.copyWith(color: p.textPrimary)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(details,
                      style:
                          AppText.caption.copyWith(color: p.textSecondary)),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: p.textTertiary),
        ],
      ),
    );
  }
}

class _EmptyDogCard extends StatelessWidget {
  const _EmptyDogCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      onTap: () => context.push(Routes.dog),
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          _DogAvatar(photoUrl: '', size: 84),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.registerDog,
                    style: AppText.title.copyWith(color: p.textPrimary)),
                const SizedBox(height: 5),
                Text(l10n.addDogPrompt,
                    style: AppText.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: p.textTertiary),
        ],
      ),
    );
  }
}

class _DogAvatar extends StatelessWidget {
  const _DogAvatar({required this.photoUrl, required this.size});
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.cardElevated,
        shape: BoxShape.circle,
        image: photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? Icon(Icons.pets, size: size * 0.4, color: p.textTertiary)
          : null,
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard(this.m);
  final Measurement m;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final isHigh = m.avgPpm >= H2.highPpm;
    final df =
        DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag());

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.latestMeasurement.toUpperCase(),
                    style:
                        AppText.overline.copyWith(color: p.textTertiary)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(m.avgPpm.toStringAsFixed(1),
                        style: AppText.numeral.copyWith(
                            fontSize: 30,
                            color: isHigh ? p.warn : p.textPrimary)),
                    const SizedBox(width: 6),
                    Text(l10n.ppm,
                        style: AppText.caption
                            .copyWith(color: p.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          Text(df.format(m.startedAt),
              style: AppText.caption.copyWith(color: p.textTertiary)),
        ],
      ),
    );
  }
}

class _QuietIconButton extends StatelessWidget {
  const _QuietIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: p.textSecondary),
        ),
      ),
    );
  }
}

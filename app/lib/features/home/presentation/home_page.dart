/// ホーム画面。犬カードを主役に、最新測定と大きな測定CTAを配置。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';
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
    final user = ref.watch(currentUserProvider).valueOrNull;
    final dog = ref.watch(selectedDogProvider);
    final connected =
        ref.watch(bleControllerProvider).status == BleStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            l10n.greeting(user?.displayName ?? ''),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),

          // ---- 犬カード(主役) ----
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.push(Routes.dog),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.outline,
                      backgroundImage: (dog?.photoUrl.isNotEmpty ?? false)
                          ? NetworkImage(dog!.photoUrl)
                          : null,
                      child: (dog?.photoUrl.isEmpty ?? true)
                          ? const Icon(Icons.pets,
                              size: 40, color: AppColors.onSurfaceVariant)
                          : null,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dog?.name ?? l10n.dogProfile,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (dog?.breed.isNotEmpty ?? false) dog!.breed,
                              if (dog?.ageYears != null) '${dog!.ageYears}歳',
                              if ((dog?.weightKg ?? 0) > 0)
                                '${dog!.weightKg}kg',
                            ].join(' ・ '),
                            style: const TextStyle(
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- 最新測定 ----
          if (dog != null)
            ref.watch(_latestMeasurementProvider(dog.id)).maybeWhen(
                  data: (m) => _LatestCard(measurement: m),
                  orElse: () => const SizedBox.shrink(),
                ),
          const SizedBox(height: 24),

          // ---- CTA ----
          FilledButton.icon(
            icon: Icon(connected ? Icons.play_arrow : Icons.bluetooth),
            label: Text(
                connected ? l10n.startMeasurement : l10n.bleConnect),
            onPressed: () =>
                context.push(connected ? Routes.measure : Routes.connect),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: Text(l10n.history),
                  onPressed: () => context.push(Routes.history),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.measurement});
  final Measurement? measurement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final m = measurement;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.latestMeasurement,
                      style: const TextStyle(
                          color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  m == null
                      ? Text(l10n.noMeasurementYet)
                      : Text(
                          '${m.avgPpm.toStringAsFixed(1)} ${l10n.ppm}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: AppColors.primary),
                        ),
                ],
              ),
            ),
            if (m != null)
              Text(
                MaterialLocalizations.of(context)
                    .formatShortDate(m.startedAt),
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

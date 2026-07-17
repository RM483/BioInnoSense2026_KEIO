/// 犬プロフィール画面。写真・基本情報の閲覧/編集。
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/dog_controller.dart';
import '../domain/dog.dart';

class DogProfilePage extends HookConsumerWidget {
  const DogProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dog = ref.watch(selectedDogProvider) ??
        const Dog(id: '', name: '');
    final saving = ref.watch(dogControllerProvider).isLoading;

    final nameCtrl = useTextEditingController(text: dog.name);
    final breedCtrl = useTextEditingController(text: dog.breed);
    final weightCtrl =
        useTextEditingController(text: dog.weightKg.toString());
    final birthday = useState<DateTime?>(dog.birthday);
    final photoBytes = useState<XFile?>(null);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dogProfile)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ---- 写真 ----
          Center(
            child: GestureDetector(
              onTap: () async {
                final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1024,
                    imageQuality: 85);
                if (picked != null) photoBytes.value = picked;
              },
              child: CircleAvatar(
                radius: 72,
                backgroundColor: AppColors.surfaceContainer,
                backgroundImage: dog.photoUrl.isNotEmpty
                    ? NetworkImage(dog.photoUrl)
                    : null,
                child: dog.photoUrl.isEmpty
                    ? const Icon(Icons.add_a_photo,
                        size: 40, color: AppColors.onSurfaceVariant)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
                labelText: l10n.dogName,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: breedCtrl,
            decoration: InputDecoration(
                labelText: l10n.breed,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: weightCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: '${l10n.weight} (kg)',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: Text(birthday.value == null
                ? l10n.birthday
                : MaterialLocalizations.of(context)
                    .formatShortDate(birthday.value!)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: birthday.value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) birthday.value = picked;
            },
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final bytes = await photoBytes.value?.readAsBytes();
                    await ref.read(dogControllerProvider.notifier).save(
                          dog.copyWith(
                            name: nameCtrl.text.trim(),
                            breed: breedCtrl.text.trim(),
                            weightKg:
                                double.tryParse(weightCtrl.text) ?? 0,
                            birthday: birthday.value,
                          ),
                          photoBytes: bytes,
                        );
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

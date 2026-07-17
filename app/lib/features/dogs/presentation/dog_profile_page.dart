/// 犬プロフィール画面。写真・基本情報の閲覧/編集。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/dog_controller.dart';
import '../domain/dog.dart';

class DogProfilePage extends HookConsumerWidget {
  const DogProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog =
        ref.watch(selectedDogProvider) ?? const Dog(id: '', name: '');
    final saving = ref.watch(dogControllerProvider).isLoading;

    final nameCtrl = useTextEditingController(text: dog.name);
    final breedCtrl = useTextEditingController(text: dog.breed);
    final weightCtrl = useTextEditingController(
        text: dog.weightKg > 0 ? dog.weightKg.toString() : '');
    final birthday = useState<DateTime?>(dog.birthday);
    final pickedPhoto = useState<XFile?>(null);
    final previewBytes = useState<Uint8List?>(null);

    Future<void> pickPhoto() async {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
      if (picked != null) {
        pickedPhoto.value = picked;
        previewBytes.value = await picked.readAsBytes();
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dogProfile)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ---- 写真 ----
          Center(
            child: GestureDetector(
              onTap: pickPhoto,
              child: Stack(
                children: [
                  Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: p.cardElevated,
                      shape: BoxShape.circle,
                      image: previewBytes.value != null
                          ? DecorationImage(
                              image: MemoryImage(previewBytes.value!),
                              fit: BoxFit.cover)
                          : dog.photoUrl.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(dog.photoUrl),
                                  fit: BoxFit.cover)
                              : null,
                    ),
                    child: (previewBytes.value == null &&
                            dog.photoUrl.isEmpty)
                        ? Icon(Icons.pets, size: 44, color: p.textTertiary)
                        : null,
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.bg, width: 3),
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 36),

          _FieldLabel(l10n.dogName),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(),
          ),
          const SizedBox(height: 20),
          _FieldLabel(l10n.breed),
          TextField(
            controller: breedCtrl,
            decoration: const InputDecoration(),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('${l10n.weight} (kg)'),
                    TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(l10n.birthday),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: birthday.value ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) birthday.value = picked;
                      },
                      child: Container(
                        height: 54,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: p.cardElevated,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          birthday.value == null
                              ? '––'
                              : DateFormat.yMMMd(Localizations.localeOf(
                                          context)
                                      .toLanguageTag())
                                  .format(birthday.value!),
                          style: AppText.body.copyWith(
                              color: birthday.value == null
                                  ? p.textTertiary
                                  : p.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),

          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final bytes = previewBytes.value;
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
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white))
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: AppText.caption
                .copyWith(color: context.palette.textSecondary)),
      );
}

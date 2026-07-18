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
  const DogProfilePage({super.key, this.initial});

  /// 編集対象の犬。null時は選択中の犬(いなければ新規登録)。
  /// Dogsタブの「追加」カードからは空のDogが渡される。
  final Dog? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = initial ??
        ref.watch(selectedDogProvider) ??
        const Dog(id: '', name: '');
    final saving = ref.watch(dogControllerProvider).isLoading;

    final nameCtrl = useTextEditingController(text: dog.name);
    // 名前は必須: 保存した時点で正式に犬を作成する (docs/21 v2.1 §5A)
    final nameFilled = useState(dog.name.trim().isNotEmpty);
    final breedCtrl = useTextEditingController(text: dog.breed);
    final weightCtrl = useTextEditingController(
        text: dog.weightKg > 0 ? dog.weightKg.toString() : '');
    final birthday = useState<DateTime?>(dog.birthday);
    final pickedPhoto = useState<XFile?>(null);
    final previewBytes = useState<Uint8List?>(null);
    final photoRemoved = useState(false); // 「現在の写真を削除」(v2.2 §6)

    Future<void> pickFrom(ImageSource source) async {
      final picked = await ImagePicker().pickImage(
          source: source, maxWidth: 1024, imageQuality: 85);
      if (picked != null) {
        pickedPhoto.value = picked;
        previewBytes.value = await picked.readAsBytes();
        photoRemoved.value = false;
      }
    }

    /// 肉球アイコン/写真タップで開く操作シート (§6):
    /// 撮る / 選ぶ / (登録済みなら)削除 / キャンセル
    Future<void> pickPhoto() async {
      final hasPhoto =
          previewBytes.value != null || dog.photoUrl.isNotEmpty;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _PhotoAction(
                  icon: Icons.photo_camera_outlined,
                  label: l10n.takePhoto,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    pickFrom(ImageSource.camera);
                  },
                ),
                _PhotoAction(
                  icon: Icons.photo_library_outlined,
                  label: l10n.choosePhoto,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    pickFrom(ImageSource.gallery);
                  },
                ),
                if (hasPhoto)
                  _PhotoAction(
                    icon: Icons.delete_outline,
                    label: l10n.removePhoto,
                    color: p.danger,
                    onTap: () {
                      // 肉球アイコンへ戻す(保存時に確定)
                      pickedPhoto.value = null;
                      previewBytes.value = null;
                      photoRemoved.value = true;
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                _PhotoAction(
                  icon: Icons.close,
                  label: l10n.cancel,
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      );
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
                          : (dog.photoUrl.isNotEmpty &&
                                  !photoRemoved.value)
                              ? DecorationImage(
                                  image: NetworkImage(dog.photoUrl),
                                  fit: BoxFit.cover)
                              : null,
                    ),
                    child: (previewBytes.value == null &&
                            (dog.photoUrl.isEmpty || photoRemoved.value))
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
                      child: Icon(Icons.camera_alt,
                          size: 16, color: p.onAccent),
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
            decoration: InputDecoration(hintText: l10n.nameRequiredHint),
            onChanged: (v) => nameFilled.value = v.trim().isNotEmpty,
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
            onPressed: (saving || !nameFilled.value)
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
                          removePhoto: photoRemoved.value,
                        );
                    if (!context.mounted) return;
                    // タブ直下では戻り先がないためスナックバーで完了を伝える
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.measurementSaved)));
                    }
                  },
            child: saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: p.onAccent))
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

/// 写真操作シートの1行
class _PhotoAction extends StatelessWidget {
  const _PhotoAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 21, color: color ?? p.textSecondary),
            const SizedBox(width: 14),
            Text(label,
                style: AppText.bodyMedium
                    .copyWith(color: color ?? p.textPrimary)),
          ],
        ),
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

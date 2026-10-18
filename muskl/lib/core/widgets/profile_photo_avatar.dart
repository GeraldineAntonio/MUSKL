import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';

class ProfilePhotoSelection {
  const ProfilePhotoSelection(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

Future<ProfilePhotoSelection?> pickProfilePhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('FOTO DE PERFIL')),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Elegir de galería'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
              ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
            ]),
          ));
  if (source == null || !context.mounted) return null;
  final image = await ImagePicker().pickImage(
      source: source, imageQuality: 85, maxWidth: 1200, maxHeight: 1200);
  if (image == null || !context.mounted) return null;
  final bytes = await image.readAsBytes();
  if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
    throw const FormatException('La foto debe pesar máximo 2 MB.');
  }
  final extension = image.name.split('.').last.toLowerCase();
  final mime = switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    _ => null,
  };
  if (mime == null) {
    throw const FormatException('Usa una imagen JPG o PNG.');
  }
  return ProfilePhotoSelection(bytes, mime);
}

class ProfilePhotoAvatar extends StatelessWidget {
  const ProfilePhotoAvatar({
    super.key,
    required this.image,
    required this.onEdit,
    this.radius = 38,
    this.name = '',
  });

  final ImageProvider? image;
  final VoidCallback onEdit;
  final double radius;
  final String name;

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              CircleAvatar(
                radius: 108,
                backgroundColor: AppColors.surfaceHigh,
                backgroundImage: image,
                child: image == null
                    ? const Icon(Icons.person,
                        size: 104, color: AppColors.accent)
                    : null,
              ),
              Positioned(
                right: -4,
                bottom: -2,
                child: IconButton.filled(
                  tooltip: 'Editar foto',
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    onEdit();
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            ]),
            if (name.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(name.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 8),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: radius * 2 + 8,
        height: radius * 2 + 8,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 4,
            top: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _showPreview(context),
              child: CircleAvatar(
                radius: radius,
                backgroundColor: AppColors.surfaceHigh,
                backgroundImage: image,
                child: image == null
                    ? Icon(Icons.person,
                        size: radius * 1.1, color: AppColors.accent)
                    : null,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.red,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.edit_outlined,
                      size: 17, color: Colors.white),
                ),
              ),
            ),
          ),
        ]),
      );
}

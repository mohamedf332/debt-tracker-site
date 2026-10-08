import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final imageStorageProvider = Provider<ImageStorageService>((ref) {
  return ImageStorageService.instance;
});

class ImageStorageService {
  ImageStorageService._();

  static final ImageStorageService instance = ImageStorageService._();

  final ImagePicker _picker = ImagePicker();
  Directory? _attachmentsDir;

  Future<Directory> get _attachmentsDirectory async {
    if (_attachmentsDir != null) return _attachmentsDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _attachmentsDir = Directory(p.join(appDir.path, 'attachments'));
    if (!await _attachmentsDir!.exists()) {
      await _attachmentsDir!.create(recursive: true);
    }
    return _attachmentsDir!;
  }

  Future<File?> pickImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image == null) return null;
      return await copyToAttachmentsDir(File(image.path));
    } catch (e) {
      return null;
    }
  }

  Future<File?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image == null) return null;
      return await copyToAttachmentsDir(File(image.path));
    } catch (e) {
      return null;
    }
  }

  Future<File> copyToAttachmentsDir(File sourceFile) async {
    final attachmentsDir = await _attachmentsDirectory;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = p.extension(sourceFile.path);
    final fileName = 'attachment_$timestamp$extension';
    final destPath = p.join(attachmentsDir.path, fileName);
    return sourceFile.copy(destPath);
  }

  /// Save raw bytes to the attachments directory and return the saved file
  Future<File> saveBytesToAttachments(Uint8List bytes, {String? extension}) async {
    final attachmentsDir = await _attachmentsDirectory;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String ext;
    if (extension != null && extension.isNotEmpty) {
      ext = extension;
    } else {
      ext = p.extension('temp');
      if (ext.isEmpty) {
        ext = '.jpg';
      }
    }
    final fileName = 'attachment_$timestamp$ext';
    final destPath = p.join(attachmentsDir.path, fileName);
    final file = File(destPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore errors - file might already be deleted
    }
  }

  Future<void> deleteFiles(List<String> filePaths) async {
    for (final path in filePaths) {
      await deleteFile(path);
    }
  }

  /// Delete all files in the attachments directory
  Future<void> clearAllAttachments() async {
    final attachmentsDir = await _attachmentsDirectory;
    if (await attachmentsDir.exists()) {
      await attachmentsDir.delete(recursive: true);
      // Recreate the directory
      await attachmentsDir.create(recursive: true);
    }
  }
}

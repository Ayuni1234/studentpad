import 'package:supabase_flutter/supabase_flutter.dart';

const listingPhotoBucket = 'listing-photos';
const maxListingPhotos = 6;

/// Reads the current array and falls back to the legacy single-photo column.
List<String> listingPhotoPaths(Map<String, dynamic> listing) {
  final rawImages = listing['images'];
  final images = rawImages is List
      ? rawImages.whereType<String>().where((path) => path.isNotEmpty)
      : const <String>[];
  final unique = <String>{...images};
  if (unique.isEmpty) {
    final legacyPath = listing['image_path'];
    if (legacyPath is String && legacyPath.isNotEmpty) unique.add(legacyPath);
  }
  return unique.take(maxListingPhotos).toList(growable: false);
}

Future<List<String>> signedListingPhotoUrls(Iterable<String> paths) async {
  final storage = Supabase.instance.client.storage.from(listingPhotoBucket);
  final urls = await Future.wait(paths.take(maxListingPhotos).map((path) async {
    try {
      return await storage.createSignedUrl(path, 60 * 60);
    } catch (_) {
      return null;
    }
  }));
  return urls.whereType<String>().toList(growable: false);
}

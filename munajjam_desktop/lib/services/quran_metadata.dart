import '../models/alignment_models.dart';

/// Marqoom terminology at the data boundary. Legacy codes remain UI/asset aliases.
class QuranMetadata {
  static Map<String, dynamic> exportAlignment({
    required String riwaya,
    required int surahNumber,
    required List<AyahSegment> ayahs,
    required List<BreathGroup> breaths,
  }) => {
    ...describe(riwaya),
    'surah_number': surahNumber,
    'total_ayahs': ayahs.length,
    'total_breath_groups': breaths.length,
    'ayahs': ayahs.map((a) => a.toJson()).toList(),
    'breath_groups': breaths.map((b) => b.toJson()).toList(),
  };

  static String canonicalRiwayah(String value) => switch (value) {
    'hafsh' || 'hafs' || 'hafs_an_asim' => 'hafs_an_asim',
    'warsh' || 'warsh_an_nafi' => 'warsh_an_nafi',
    _ => throw FormatException('Unsupported riwayah: $value'),
  };

  static String legacyRiwaya(String value) =>
      canonicalRiwayah(value) == 'warsh_an_nafi' ? 'warsh' : 'hafsh';

  static String numbering(String value) =>
      canonicalRiwayah(value) == 'warsh_an_nafi' ? 'madani_last' : 'kufi';

  static Map<String, dynamic> describe(String value) => {
    'riwayah': canonicalRiwayah(value),
    'ayah_numbering_system': numbering(value),
    'time_unit': 'second',
    'time_origin': 'start_of_audio_file',
    'word_segmentation':
        'Aligned spoken segments in chronological order; '
        'may contain repetition or multiple written words. Array indexes are '
        'not Quran word positions. Basmalah follows the supplied text.',
    'format_version': 2,
  };

  /// Reject a numbering mismatch before merging imported text with local assets.
  static String? importedRiwaya(Map<String, dynamic> data) {
    if (data['time_unit'] != null && data['time_unit'] != 'second') {
      throw const FormatException('Only second-based timings are supported');
    }
    if (data['time_origin'] != null &&
        data['time_origin'] != 'start_of_audio_file') {
      throw const FormatException('Unsupported time origin');
    }
    final value = data['riwayah'] ?? data['riwaya'];
    final system = data['ayah_numbering_system'];
    if (value == null) {
      if (system != null) {
        throw const FormatException(
          'A numbered import must declare its riwayah',
        );
      }
      return null; // Legacy files use the explicitly selected UI riwayah.
    }
    final legacy = legacyRiwaya(value.toString());
    if (system != null && system != numbering(legacy)) {
      throw const FormatException(
        'Unsupported ayah numbering for this riwayah',
      );
    }
    return legacy;
  }
}

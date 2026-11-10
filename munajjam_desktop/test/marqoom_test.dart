import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/models/alignment_models.dart';
import 'package:munajjam_desktop/providers/alignment_provider.dart';
import 'package:munajjam_desktop/services/quran_data_service.dart';
import 'package:munajjam_desktop/services/quran_metadata.dart';
import 'package:munajjam_desktop/services/aligner_api_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'HTTP client sends canonical code alongside the legacy compatibility field',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final temp = Directory.systemTemp.createTempSync('munajjam-metadata-');
        addTearDown(() async {
          await server.close(force: true);
          temp.deleteSync(recursive: true);
        });
        final audio = File('${temp.path}/test.wav')..writeAsBytesSync([0, 1]);
        final received = server.first.then((request) async {
          final body = await utf8.decoder.bind(request).join();
          expect(body, contains('name="riwayah"\r\n\r\nwarsh_an_nafi'));
          expect(body, contains('name="riwaya"\r\n\r\nwarsh'));
          request.response.write('{"job_id":"test-job"}');
          await request.response.close();
        });
        final api = AlignerApiService(
          baseUrl: 'http://127.0.0.1:${server.port}',
        );
        expect(
          await api.startAlignmentJob(
            surahId: 1,
            audioFile: audio,
            riwaya: 'warsh',
          ),
          'test-job',
        );
        await received;
      }, _RealHttpOverrides());
    },
  );
  for (final legacy in ['hafsh', 'warsh']) {
    test('$legacy export carries its numbering and round trips', () async {
      final provider = AlignmentProvider()..setRiwaya(legacy);
      addTearDown(provider.dispose);
      final texts = await QuranDataService().getSurahAyahs(1, riwaya: legacy);
      await provider.applyAlignmentResult(
        ayahs: List.generate(
          texts.length,
          (i) => AyahSegment(
            ayahNumber: i + 1,
            start: i * 2.0,
            end: i * 2.0 + 2,
            text: texts[i],
            words: [],
          ),
        ),
        breaths: [],
        surahId: 1,
      );
      // Changing the controls cannot relabel timings already in the editor.
      provider.setRiwaya(legacy == 'warsh' ? 'hafsh' : 'warsh');
      final exported = provider.generateExportJson();
      final data = jsonDecode(exported);
      expect(data['riwayah'], QuranMetadata.canonicalRiwayah(legacy));
      expect(data['ayah_numbering_system'], QuranMetadata.numbering(legacy));
      expect(data['surah_number'], 1);
      expect(data['time_unit'], 'second');
      final imported = AlignmentProvider();
      addTearDown(imported.dispose);
      expect(
        await imported.importAlignmentFromJson(jsonString: exported),
        isTrue,
      );
      expect(imported.riwaya, legacy);
      expect(imported.segments.first.text, texts.first);
      expect(
        jsonDecode(imported.generateExportJson())['riwayah'],
        data['riwayah'],
      );
      final destination = Platform.environment['MARQOOM_EXPORT_DIR'];
      if (destination != null) {
        final dir = Directory(destination)..createSync(recursive: true);
        File('${dir.path}/$legacy.json').writeAsStringSync(exported);
      }
    });
  }
  test('legacy files remain readable without invented riwayah metadata', () {
    final parsed = QuranDataService().parseAlignmentJson(
      jsonEncode({
        'surah_id': 2,
        'ayahs': [
          {'ayah_number': 255, 'start': 1, 'end': 2, 'text': 'test'},
        ],
      }),
    );
    expect(parsed?['surahId'], 2);
    expect(parsed?['riwaya'], isNull);
  });
  test('unsupported numbering, riwayah and time units reject the import', () {
    for (final metadata in [
      {'riwayah': 'unknown'},
      {'riwayah': 'warsh_an_nafi', 'ayah_numbering_system': 'kufi'},
      {'riwayah': 'hafs_an_asim', 'time_unit': 'millisecond'},
      {'riwayah': 'hafs_an_asim', 'time_origin': 'segment_start'},
    ]) {
      expect(
        QuranDataService().parseAlignmentJson(
          jsonEncode({...metadata, 'surah_number': 1, 'ayahs': []}),
        ),
        isNull,
      );
    }
  });
  test(
    'explicit imported text is preserved instead of being overwritten',
    () async {
      final provider = AlignmentProvider();
      addTearDown(provider.dispose);
      expect(
        await provider.importAlignmentFromJson(
          jsonString: jsonEncode({
            'riwayah': 'warsh_an_nafi',
            'ayah_numbering_system': 'madani_last',
            'surah_number': 1,
            'ayahs': [
              {
                'ayah_number': 1,
                'start': 0,
                'end': 1,
                'text': 'preserve source text',
              },
            ],
          }),
        ),
        isTrue,
      );
      expect(provider.segments.single.text, 'preserve source text');
    },
  );
}

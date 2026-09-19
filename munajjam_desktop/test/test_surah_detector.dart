import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/models/batch_alignment_item.dart';

void main() {
  test('SurahFileNameDetector detects surahs correctly in complex filenames', () {
    final res1 = SurahFileNameDetector.detectSurah('QR_SC1447_Bdr-Atturki_As-Hf_mdd_BR128_001.mp3');
    expect(res1.$1, 1);
    expect(res1.$2, 'الفاتحة');

    final res2 = SurahFileNameDetector.detectSurah('QR_SC1447_Bdr-Atturki_As-Hf_mdd_BR128_018.mp3');
    expect(res2.$1, 18);
    expect(res2.$2, 'الكهف');

    final res3 = SurahFileNameDetector.detectSurah('001.mp3');
    expect(res3.$1, 1);

    final res4 = SurahFileNameDetector.detectSurah('002 - البقرة.mp3');
    expect(res4.$1, 2);
    expect(res4.$2, 'البقرة');

    final res5 = SurahFileNameDetector.detectSurah('Surah_036_Yaseen.wav');
    expect(res5.$1, 36);
    expect(res5.$2, 'يس');

    final res6 = SurahFileNameDetector.detectSurah('112_Al-Ikhlas.m4a');
    expect(res6.$1, 112);
    expect(res6.$2, 'الإخلاص');

    final res7 = SurahFileNameDetector.detectSurah('سورة_الكهف_1445.mp3');
    expect(res7.$1, 18);

    final res8 = SurahFileNameDetector.detectSurah('Abdulbasit_1447_067.mp3');
    expect(res8.$1, 67);
    expect(res8.$2, 'الملك');

    // اختبارات السور القصيرة (يس، طه، ص، ق)
    final resYaseen1 = SurahFileNameDetector.detectSurah('سورة يس.mp3');
    expect(resYaseen1.$1, 36);
    expect(resYaseen1.$2, 'يس');

    final resYaseen2 = SurahFileNameDetector.detectSurah('يس.mp3');
    expect(resYaseen2.$1, 36);
    expect(resYaseen2.$2, 'يس');

    final resTaha1 = SurahFileNameDetector.detectSurah('طه.mp3');
    expect(resTaha1.$1, 20);
    expect(resTaha1.$2, 'طه');

    final resTaha2 = SurahFileNameDetector.detectSurah('سورة طه.mp3');
    expect(resTaha2.$1, 20);
    expect(resTaha2.$2, 'طه');

    final resSad = SurahFileNameDetector.detectSurah('سورة ص.mp3');
    expect(resSad.$1, 38);
    expect(resSad.$2, 'ص');

    final resQaf = SurahFileNameDetector.detectSurah('سورة ق.mp3');
    expect(resQaf.$1, 50);
    expect(resQaf.$2, 'ق');

    final resSudais = SurahFileNameDetector.detectSurah('الشيخ السديس سورة الكهف.mp3');
    expect(resSudais.$1, 18);
    expect(resSudais.$2, 'الكهف');

    final resNisaa = SurahFileNameDetector.detectSurah('4.mp3');
    expect(resNisaa.$1, 4);
    expect(resNisaa.$2, 'النساء');
  });
}

# مُنجّم | محطة التزمين القرآني الذكي (Munajjam Quran Alignment Workstation)

[![Marqoom terminology v0.1](https://img.shields.io/badge/Marqoom-terminology%20v0.1-8c6a2c)](https://marqoom-specs.com/ar/docs/terms) [![Quranic terminology](https://github.com/alinice1998/munajjam-desktop/actions/workflows/terminology.yml/badge.svg)](https://github.com/alinice1998/munajjam-desktop/actions/workflows/terminology.yml)

منظومة متطورة مفتوحة المصدر لتزمين ومحاذاة التلاوات القرآنية بدقة متناهية على مستوى الآيات والوقف والنَّفَس والكلمات، تجمع بين واجهة مكتبية تفاعلية حديثة مبنية بـ **Flutter** ومحرك ذكاء اصطناعي هجين فائق الدقة مبني بـ **Python** ونماذج **ONNX Runtime** المتسارعة بالـ GPU.

---

## 🌟 محركات التزمين المتوفرة

| المحرك | المعرف (`id`) | النوع | التقنية والميزات |
| :--- | :---: | :---: | :--- |
| **المحرك الهجين فائق الدقة (مُنجّم v2)** | `hybrid` | **الافتراضي (موصى به)** | تقطيع الأنفاس والوقف العصبي عبر `recitation-segmenter-v2` (GPU) + كشف الأركان بـ Zipformer v3 + تدقيق مجهري قسري بـ Wav2Vec2 XLSR-53. |
| **المحرك التجريبي الذكي (الضبابي Fuzzy)** | `hybrid_fuzzy` | **تجريبي** | تقطيع الأنفاس العصبي + تفريغ Zipformer الحر ومطابقة تقريبية مرنة (للتعامل الفائق مع تلاوات التحقيق الصعبة وتكرار المقاطع). |
| **محرك Zipformer الكلاسيكي (فائق السرعة)** | `zipformer` | **خفيف وسريع** | تزمين مباشر بنموذج `QuranLab/zipformer_p-arabic-v3` فقط، يعمل بخفة متناهية على أي معالج عادي (CPU) دون الحاجة لبطاقات رسوميات. |

---

## 🏗️ مكونات النظام (Architecture)

1. **تطبيق سطح المكتب (`munajjam_desktop`):**
   - واجهة مستخدم احترافية بالكامل عبر Flutter Desktop (Windows).
   - مشغل صوتي متزامن مع Waveform ومحرر بصري متقدم للتوقيتات (QA Editor).
   - نافذة مخصصة لتزمين الختمات الكاملة والدفعات الجماعية (Batch Alignment) مع ميزة إيقاف تشغيل الحاسوب التلقائي وحفظ ملف الـ Manifest.
   - دعم كامل للغتين (العربية والإنجليزية) مع التبديل اللحظي.

2. **محرك الذكاء الاصطناعي والخادم المحلي (`munajjam_server.py` & `hybrid_aligner`):**
   - خادم FastAPI محلي يتواصل مع الواجهة عبر واجهات REST API مع بث نسبة التقدم اللحظية بدقة الفريم.
   - تسريع عتادي مباشر عبر `DirectML` و `ONNXRuntime` لدعم كروت الشاشة الحديثة.

3. **بيانات المصحف الشريف (`data/`):**
   - نصوص القرآن الكريم كاملة بروايتي حفص عن عاصم وورش عن نافع مع توكنات التزمين.

---

## 🚀 التشغيل والتطوير للمطورين

### 1. إعداد خادم الذكاء الاصطناعي
```bash
# تثبيت الحزم المطلوبة
pip install -r requirements.txt

# تحميل النماذج المجهزة بصيغة ONNX DirectML (حزمة نماذج مُنجّم الرسمية)
python download_models.py

# تشغيل الخادم
python munajjam_server.py
```
*(أو لمستخدمي ويندوز: انقر نقراً مزدوجاً على `run_local.bat` لتنفيذ كل ما سبق تلقائياً).*

> **ملاحظة:** يتم تنزيل كافة النماذج العصبية المجهزة تلقائياً من المستودع الرسمي المفتوح على Hugging Face:
> [`Alimalas/munajjam-onnx-models`](https://huggingface.co/Alimalas/munajjam-onnx-models)
> بصيغة ONNX فائقة السرعة ودون الحاجة إلى مفاتيح وصول (Tokens) أو أي خطوات تصدير إضافية.

### 2. تشغيل واجهة فلاتر المكتبية
```bash
cd munajjam_desktop
flutter pub get
flutter run -d windows
```

---

## 🏷️ المصطلحات القرآنية

يتبع مُنجّم [معيار المصطلحات القرآنية v0.1](https://marqoom-specs.com/ar/docs/terms) من مرقوم في أسماء الكود وفي ملفات JSON التي يصدّرها: توقيت الآية `AyahTiming` وتوقيت الكلمة `WordTiming`، والرواية `riwayah` برموز سجل القراءات (`hafs_an_asim` و`warsh_an_nafi`)، وتصنيف السور `makki` و`madani`. وتعرض الواجهة أسماء السور اللاتينية كما في سجل السور (`Fatihah` و`Baqarah`).

تفحص الأسماءَ أداةُ [Quranic terminology lint](https://github.com/marqoom-specs/quranic-terminology-lint) قبل كل commit، وفي كل Pull Request عبر GitHub Actions. لتفعيلها عندك:

```bash
pip install pre-commit
pre-commit install
```

ولمراجعة المشروع كاملًا: `pre-commit run quranic-terminology --all-files`. الاستثناءات وسبب كل منها في `.terminology.json`.

---

## 📦 بناء حزمة التثبيت للمستخدم النهائي (Installer)

يتم حزم التطبيق والخادم والنماذج في ملف تثبيت واحد عبر **Inno Setup**:
1. قم ببناء نسخة الإنتاج من فلاتر:
   ```bash
   cd munajjam_desktop
   flutter build windows --release
   ```
2. افتح ملف `munajjam_desktop/installer.iss` في برنامج **Inno Setup Compiler** واضغط **Compile**.
3. سيتم إنشاء ملف التثبيت النهائي داخل مجلد `installer_output/`.

---

## 📄 الترخيص (License)
مشروع حر ومفتوح المصدر مخصص لخدمة كتاب الله عز وجل والباحثين في معالجة الصوتيات القرآنية.

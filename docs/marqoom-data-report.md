# quranic-data 0.5.0 · Marqoom registries (terminology v0.1)

Read 12 data files (6.0 MB) in 61 ms. 4 are copies of other files, reported once. **0 errors, 5 warnings, 1 note.**

## Quran data

| Where | Shape and size | Numbering | Says about itself | Sajdah marks |
|---|---|---|---|---|
| `data/quran_hafsh.json` (same file at munajjam_desktop/assets/data/quran_hafsh.json) | ayahs keyed by surah number · 114 surahs · 6236 ayahs | fits kufi (114/114 surahs) | states hafs_an_asim, kufi | 15 marked, all at the registry's places |
| `data/quran_warsh.json` (same file at munajjam_desktop/assets/data/quran_warsh.json) | ayahs keyed by surah number · 114 surahs · 6214 ayahs | fits madani_last (113/114 surahs) | states warsh_an_nafi, madani_last | 15 marked; the registry's places are Kufi ayah numbers, so only the number in each surah is compared: it matches in 14 surahs |
| `data/surahs.json` (same file at munajjam_desktop/assets/data/surahs.json) | surah table with ayah counts · 114 surahs · 6214 ayahs | fits madani_last (113/114 surahs) | states madani_last |  |
| `examples/exports/hafsh.json` | one surah's ayahs · 1 surah · 7 ayahs | fits any system (1/1 surah) | states hafs_an_asim, kufi |  |
| `examples/exports/warsh.json` | one surah's ayahs · 1 surah · 7 ayahs | fits any system (1/1 surah) | states warsh_an_nafi, madani_last |  |

## Meaning — what a consumer would read wrongly

- **warning** — 1:1 begins with the basmalah and continues into the ayah; word positions in 1:1 are 4 higher than in data where the basmalah stands apart or is not counted
  - At: `examples/exports/warsh.json:16`
  - Fix: state the word segmentation (data.files.<file>.word_segmentation), or keep the basmalah separate
  - Basis: rules 071, 072; dictionary: basmalah
- **warning** — holds word keys (`surah:ayah:word`) but doesn't state the text or word segmentation they count by, or the numbering, so the ayah part is read as Kufi
  - At: `data/ground_truth.json:1 [ref_from] ×128 (+ 1 copy)`, `data/ground_truth.json:1 [ref_to] ×128 (+ 1 copy)`
  - Fix: state the text and segmentation (data.files.<file>.word_segmentation), and the riwayah
  - Basis: rules 071, 072
- **warning** — states `madani_last` and matches the registry in 113 of 114 surahs; surah 17: 110 here, 111 in the registry
  - At: `data/quran_warsh.json (+ 1 copy)`, `data/surahs.json (+ 1 copy)`
  - Fix: check these surahs against the source edition; if the data is right, the registry needs review
  - Basis: registries: ayah_counts
- **note** — 1:1 begins with the basmalah and continues into the ayah; word positions in 1:1 are 4 higher than in data where the basmalah stands apart or is not counted
  - At: `data/quran_warsh.json:3 (+ 1 copy)`
  - Fix: state the word segmentation (data.files.<file>.word_segmentation), or keep the basmalah separate
  - Basis: rules 071, 072; dictionary: basmalah

## Registry evidence

Where data disagrees with Marqoom's `ayah_counts`:

- madani_last, surah 17: registry 111; data says data/quran_warsh.json (110; + 1 copy), data/surahs.json (110; + 1 copy)

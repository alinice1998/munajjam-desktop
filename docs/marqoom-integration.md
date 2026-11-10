# Marqoom integration

Munajjam adopts the Marqoom terminology v0.1 registry codes at its public data boundaries. This is not certification of the Quran text or of acoustic alignment accuracy, and it does not claim to implement a finalized Marqoom timing file format (that format is still being developed).

## Export format 2

Individual exports and batch exports share `QuranMetadata.exportAlignment`. The batch manifest uses the same metadata definitions.

| Field | Meaning |
| --- | --- |
| `format_version` | Munajjam format version, now 2 |
| `surah_number` | Quran reference number, replacing the old `surah_id` export key |
| `riwayah` | `hafs_an_asim` or `warsh_an_nafi` |
| `ayah_numbering_system` | `kufi` for the bundled Hafs data, `madani_last` for the bundled Warsh data |
| `time_unit` | `second` |
| `time_origin` | `start_of_audio_file` |
| `word_segmentation` | Explicitly describes chronological spoken segments, including possible repetitions and multiword segments; array offsets are not Quran word positions |

`time_unit`, `time_origin`, `format_version`, and the container layout are Munajjam's documented interchange contract, not a claim that Marqoom has finalized those fields. Existing `ayahs`, `words`, and `breath_groups` arrays retain their structure. Consumers of old exports should accept `surah_number ?? surah_id` and `riwayah ?? riwaya` and normalize legacy codes. New exports do not contain the old `surah_id` or `riwaya` keys.

The editor retains the riwayah associated with loaded timings even if the user changes the controls before exporting. Import accepts old files and new files, restores explicit riwayah metadata, and preserves supplied ayah text. An unsupported riwayah, incompatible numbering system, explicit non-second time unit or different time origin is rejected. Legacy files without metadata continue to use the user's selected riwayah; their identity cannot be inferred reliably from the file alone.

## Client and server

Flutter sends canonical `riwayah` plus legacy `riwaya` for old servers. All three alignment endpoints accept canonical values, and legacy clients remain supported. If both fields are sent, the canonical field takes precedence. New job/status and synchronous responses include riwayah, numbering, time-unit/origin and segmentation metadata. Bundled filenames remain unchanged. Missing Warsh assets are not silently replaced by Hafs.

The Python helper is included in both full and patch installer source lists. No model or audio inference algorithm is changed by this integration.

## Checks

Install `pre-commit`, then run from the repository root:

```sh
python -m pre_commit install
python -m pre_commit run --all-files
python -m unittest discover -s tests -v
python -m unittest discover -s hybrid_aligner/tests -v
cd munajjam_desktop
flutter test
```

The data hook is pinned to `v0.5.0`; A ready-to-enable [GitHub Actions template](marqoom-workflow.yml) runs it on pushes and pull requests. The current GitHub credential lacks the workflow scope, so the template is provided in docs rather than installed as an active workflow. Copy it to .github/workflows/marqoom.yml using a connection with that scope to enable it. The naming-only scan is not a blocking project-wide migration: legacy UI identifiers and asset filenames are deliberately preserved. No unsafe automatic renaming is used. `.terminology.json` declares the bundled datasets separately from published files; consumers of exports do not need that configuration.

`examples/exports` contains synthetic timing fixtures emitted by the actual Flutter exporter for the bundled Fatihah texts, not measured recitation timings. Set `MARQOOM_EXPORT_DIR` when running `test/marqoom_test.dart` to regenerate them. Tests cover both riwayahs, metadata round trips, legacy imports, incompatible metadata, and preservation of imported text. Python tests exercise the actual loader and HTTP endpoint functions without loading inference models.

## Remaining findings

The checked-in [data report](marqoom-data-report.md) has **0 errors, 5 warnings, 1 note**. Warnings are visible and do not block the default hook; `--strict` would fail. They are not suppressed:

- The bundled Warsh text and surah table have 110 ayahs in surah 17; the v0.5.0 registry has 111. The other 113 surah counts match. Source data and registry require scholarly/source review; no Quran text was altered to satisfy a counter.
- `ground_truth.json` contains word references without documented numbering/text segmentation. Its provenance was not invented.
- The Warsh Fatihah starts with the basmalah joined to the first ayah. The published export explicitly carries `word_segmentation`, but v0.5.0's check reads this declaration from configuration, not from the published JSON. It still warns; published files cannot rely on a private configuration exemption.

Passing the data hook means no findings classified as errors; it is not a guarantee that every possible data problem is detected. Inference quality and a listening review are outside these checks.

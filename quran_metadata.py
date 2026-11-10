"""Resolve public Marqoom codes to the unchanged bundled asset filenames."""

def legacy_riwaya(value: str) -> str:
    aliases = {
        "hafsh": "hafsh", "hafs": "hafsh", "hafs_an_asim": "hafsh",
        "warsh": "warsh", "warsh_an_nafi": "warsh",
    }
    try:
        return aliases[value]
    except KeyError:
        raise ValueError(f"Unsupported riwayah: {value}") from None


def describe_riwayah(value: str) -> dict:
    legacy = legacy_riwaya(value)
    return {
        "riwayah": "warsh_an_nafi" if legacy == "warsh" else "hafs_an_asim",
        "ayah_numbering_system": "madani_last" if legacy == "warsh" else "kufi",
        "time_unit": "second",
        "time_origin": "start_of_audio_file",
        "word_segmentation": "Aligned spoken segments, possibly repeated or multiword; array indexes are not Quran word positions.",
    }

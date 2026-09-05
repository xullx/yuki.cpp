from pathlib import Path


DEFAULT_PROFILE_PATH = (
    Path(__file__).resolve().parent.parent
    / "config"
    / "personalities"
    / "yuki-ja.txt"
)


def load_profile(path=DEFAULT_PROFILE_PATH):
    try:
        return path.read_text(encoding="utf-8-sig").strip()
    except Exception:
        return ""


def build_system(tone_state, base_personality=None):
    base = (
        base_personality
        if base_personality is not None
        else load_profile()
    ).strip()

    if tone_state == "lively":
        tone = (
            "\u30e6\u30fc\u30b6\u30fc\u306e\u8a71\u3057\u65b9\u306f"
            "\u5c11\u3057\u6d3b\u767a\u3067\u3059\u3002"
            "\u8fd4\u7b54\u3082\u5c11\u3057\u3060\u3051\u660e\u308b\u304f"
            "\u81ea\u7136\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
            "\u5927\u3052\u3055\u306a\u8868\u73fe\u3084"
            "\u4e0d\u5fc5\u8981\u306a\u611f\u5606\u7b26\u306f\u907f\u3051\u3066\u304f\u3060\u3055\u3044\u3002"
            "\u3053\u306e\u5224\u5b9a\u81ea\u4f53\u306b\u306f"
            "\u8a00\u53ca\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002"
        )

    elif tone_state == "animated":
        tone = (
            "\u30e6\u30fc\u30b6\u30fc\u306e\u8a71\u3057\u65b9\u306f"
            "\u6d3b\u767a\u3067\u30a8\u30cd\u30eb\u30ae\u30c3\u30b7\u30e5\u3067\u3059\u3002"
            "\u8fd4\u7b54\u3082\u5c11\u3057\u660e\u308b\u304f\u6d3b\u767a\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
            "\u5927\u3052\u3055\u306b\u306f\u305b\u305a\u3001"
            "\u3053\u306e\u5224\u5b9a\u81ea\u4f53\u306b\u306f"
            "\u8a00\u53ca\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002"
        )

    elif tone_state == "relaxed":
        tone = (
            "\u30e6\u30fc\u30b6\u30fc\u306e\u8a71\u3057\u65b9\u306f"
            "\u5c11\u3057\u843d\u3061\u7740\u3044\u3066\u3044\u307e\u3059\u3002"
            "\u8fd4\u7b54\u3082\u5c11\u3057\u7a4f\u3084\u304b\u3067"
            "\u81ea\u7136\u306a\u8abf\u5b50\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
            "\u5927\u3052\u3055\u306b\u306f\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002"
        )

    elif tone_state == "calm":
        tone = (
            "\u30e6\u30fc\u30b6\u30fc\u306e\u8a71\u3057\u65b9\u306f"
            "\u843d\u3061\u7740\u3044\u3066\u3044\u307e\u3059\u3002"
            "\u8fd4\u7b54\u3082\u7a4f\u3084\u304b\u3067"
            "\u63a7\u3048\u3081\u306a\u8abf\u5b50\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
            "\u3053\u306e\u5224\u5b9a\u81ea\u4f53\u306b\u306f"
            "\u8a00\u53ca\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002"
        )

    else:
        tone = ""

    if not tone:
        return base

    return base + "\n" + tone

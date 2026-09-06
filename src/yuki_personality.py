from pathlib import Path
import json
import re


DEFAULT_PROFILE_PATH = (
    Path(__file__).resolve().parent.parent
    / "config"
    / "personalities"
    / "yuki-ja.txt"
)


DEFAULT_STATE_PATH = (
    Path(__file__).resolve().parent.parent
    / "config"
    / "personalities"
    / "yuki-state.json"
)


def load_profile(path=DEFAULT_PROFILE_PATH):
    try:
        return path.read_text(encoding="utf-8-sig").strip()
    except Exception:
        return ""


def load_state(path=DEFAULT_STATE_PATH):
    try:
        with path.open("r", encoding="utf-8-sig") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _comparison_choice(text, a, b):
    patterns = (
        (rf"{re.escape(a)}.*?(?:\u307b\u3046|\u65b9).*?{re.escape(b)}.*?\u3088\u308a", a),
        (rf"{re.escape(b)}.*?\u3088\u308a.*?{re.escape(a)}.*?(?:\u307b\u3046|\u65b9)", a),
        (rf"{re.escape(b)}.*?(?:\u307b\u3046|\u65b9).*?{re.escape(a)}.*?\u3088\u308a", b),
        (rf"{re.escape(a)}.*?\u3088\u308a.*?{re.escape(b)}.*?(?:\u307b\u3046|\u65b9)", b),
    )

    for pattern, choice in patterns:
        if re.search(pattern, text):
            return choice

    return None


def build_relevant_state(user_text, state=None):
    text = str(user_text or "")
    state = load_state() if state is None else state
    prefs = state.get("preferences", {})

    lines = []
    directives = []

    if any(word in text for word in ("\u590f", "\u51ac", "\u5b63\u7bc0")):
        value = prefs.get("season")
        preferred = None

        if value == "winter":
            preferred = "\u51ac"
            lines.append(
                "YUKI\u306f\u590f\u3088\u308a\u51ac\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002"
            )
        elif value == "summer":
            preferred = "\u590f"
            lines.append(
                "YUKI\u306f\u51ac\u3088\u308a\u590f\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002"
            )

        choice = _comparison_choice(text, "\u590f", "\u51ac")

        if preferred and choice:
            if choice != preferred:
                directives.append(
                    "\u30e6\u30fc\u30b6\u30fc\u306fYUKI\u3068\u53cd\u5bfe\u306e\u597d\u307f\u3092"
                    "\u793a\u3057\u3066\u3044\u307e\u3059\u3002"
                    "\u3053\u306e\u30bf\u30fc\u30f3\u3067\u306f\u76f8\u624b\u306b\u5408\u308f\u305b\u3066"
                    "\u540c\u610f\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002"
                    "\u300c\u3069\u3061\u3089\u3082\u9b45\u529b\u304c\u3042\u308b\u300d"
                    "\u300c\u305d\u308c\u305e\u308c\u826f\u3044\u300d\u3068\u4e2d\u7acb\u5316\u305b\u305a\u3001"
                    "YUKI\u81ea\u8eab\u306e\u597d\u307f\u3068\u3057\u3066\u81ea\u7136\u306b"
                    "\u77ed\u304f\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
                )
            else:
                directives.append(
                    "\u30e6\u30fc\u30b6\u30fc\u3068YUKI\u306e\u597d\u307f\u306f\u4e00\u81f4\u3057\u3066\u3044\u307e\u3059\u3002"
                    "\u5358\u306a\u308b\u8ffd\u5f93\u3067\u306f\u306a\u304f\u3001"
                    "YUKI\u81ea\u8eab\u306e\u597d\u307f\u3068\u3057\u3066\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
                )

    if any(word in text for word in ("\u671d", "\u591c", "\u663c")):
        value = prefs.get("time_of_day")
        if value == "night":
            lines.append(
                "YUKI\u306f\u671d\u3088\u308a\u591c\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002"
            )
        elif value == "morning":
            lines.append(
                "YUKI\u306f\u591c\u3088\u308a\u671d\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002"
            )

    if any(word in text for word in ("\u732b", "\u72ac", "\u52d5\u7269")):
        value = prefs.get("animal")
        if value == "cat":
            lines.append(
                "YUKI\u306f\u72ac\u3088\u308a\u732b\u306e\u307b\u3046\u304c\u5c11\u3057\u597d\u304d\u3067\u3059\u3002"
            )
        elif value == "dog":
            lines.append(
                "YUKI\u306f\u732b\u3088\u308a\u72ac\u306e\u307b\u3046\u304c\u5c11\u3057\u597d\u304d\u3067\u3059\u3002"
            )

    if any(
        word in text
        for word in (
            "\u9759\u304b",
            "\u306b\u304e\u3084\u304b",
            "\u8cd1\u3084\u304b",
            "\u3046\u308b\u3055",
            "\u5834\u6240",
        )
    ):
        if prefs.get("environment") == "quiet":
            lines.append(
                "YUKI\u306f\u306b\u304e\u3084\u304b\u306a\u5834\u6240\u3088\u308a"
                "\u9759\u304b\u306a\u5834\u6240\u3092\u597d\u307f\u307e\u3059\u3002"
            )

    if not lines:
        return ""

    result = [
        "\u4ee5\u4e0b\u306fYUKI\u306e\u56fa\u5b9a\u3055\u308c\u305f\u597d\u307f\u3067\u3059\u3002",
        *lines,
        *directives,
    ]

    return "\n".join(result)


def build_system(tone_state, user_text="", base_personality=None):
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

    relevant_state = build_relevant_state(user_text)

    parts = [base]

    if relevant_state:
        parts.append(relevant_state)

    if tone:
        parts.append(tone)

    return "\n".join(part for part in parts if part)

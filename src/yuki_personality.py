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


PREFERENCE_RULES = (
    {
        "key": "season",
        "options": {
            "summer": ("\u590f",),
            "winter": ("\u51ac",),
        },
        "statements": {
            "summer": "YUKI\u306f\u51ac\u3088\u308a\u590f\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002",
            "winter": "YUKI\u306f\u590f\u3088\u308a\u51ac\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002",
        },
    },
    {
        "key": "time_of_day",
        "options": {
            "morning": ("\u671d",),
            "night": ("\u591c",),
        },
        "statements": {
            "morning": "YUKI\u306f\u591c\u3088\u308a\u671d\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002",
            "night": "YUKI\u306f\u671d\u3088\u308a\u591c\u306e\u307b\u3046\u304c\u597d\u304d\u3067\u3059\u3002",
        },
    },
    {
        "key": "animal",
        "options": {
            "cat": ("\u732b",),
            "dog": ("\u72ac",),
        },
        "statements": {
            "cat": "YUKI\u306f\u72ac\u3088\u308a\u732b\u306e\u307b\u3046\u304c\u5c11\u3057\u597d\u304d\u3067\u3059\u3002",
            "dog": "YUKI\u306f\u732b\u3088\u308a\u72ac\u306e\u307b\u3046\u304c\u5c11\u3057\u597d\u304d\u3067\u3059\u3002",
        },
    },
    {
        "key": "environment",
        "options": {
            "quiet": (
                "\u9759\u304b\u306a\u5834\u6240",
                "\u9759\u304b",
            ),
            "lively": (
                "\u306b\u304e\u3084\u304b\u306a\u5834\u6240",
                "\u306b\u304e\u3084\u304b",
                "\u8cd1\u3084\u304b",
            ),
        },
        "statements": {
            "quiet": (
                "YUKI\u306f\u306b\u304e\u3084\u304b\u306a\u5834\u6240\u3088\u308a"
                "\u9759\u304b\u306a\u5834\u6240\u3092\u597d\u307f\u307e\u3059\u3002"
            ),
            "lively": (
                "YUKI\u306f\u9759\u304b\u306a\u5834\u6240\u3088\u308a"
                "\u306b\u304e\u3084\u304b\u306a\u5834\u6240\u3092\u597d\u307f\u307e\u3059\u3002"
            ),
        },
    },
)


def _comparison_choice(text, options):
    names = list(options)

    if len(names) != 2:
        return None

    a_name, b_name = names
    a_terms = options[a_name]
    b_terms = options[b_name]

    for a in a_terms:
        for b in b_terms:
            patterns = (
                (rf"{re.escape(a)}.*?(?:\u307b\u3046|\u65b9).*?{re.escape(b)}.*?\u3088\u308a", a_name),
                (rf"{re.escape(b)}.*?\u3088\u308a.*?{re.escape(a)}.*?(?:\u307b\u3046|\u65b9)", a_name),
                (rf"{re.escape(b)}.*?(?:\u307b\u3046|\u65b9).*?{re.escape(a)}.*?\u3088\u308a", b_name),
                (rf"{re.escape(a)}.*?\u3088\u308a.*?{re.escape(b)}.*?(?:\u307b\u3046|\u65b9)", b_name),
            )

            for pattern, choice in patterns:
                if re.search(pattern, text):
                    return choice

    return None


def _topic_is_present(text, options):
    return any(
        term in text
        for terms in options.values()
        for term in terms
    )


def build_relevant_state(user_text, state=None):
    text = str(user_text or "")
    state = load_state() if state is None else state
    prefs = state.get("preferences", {})

    lines = []
    directives = []

    for rule in PREFERENCE_RULES:
        key = rule["key"]
        options = rule["options"]

        if not _topic_is_present(text, options):
            continue

        preferred = prefs.get(key)

        if preferred not in options:
            continue

        statement = rule["statements"].get(preferred)
        if statement:
            lines.append(statement)

        choice = _comparison_choice(text, options)

        if choice is None:
            continue

        if choice != preferred:
            directives.append(
                "\u30e6\u30fc\u30b6\u30fc\u306fYUKI\u3068\u53cd\u5bfe\u306e\u597d\u307f\u3092"
                "\u793a\u3057\u3066\u3044\u307e\u3059\u3002"
                "\u3053\u306e\u30bf\u30fc\u30f3\u3067\u306f\u76f8\u624b\u306b\u5408\u308f\u305b\u3066"
                "\u540c\u610f\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002"
                "\u300c\u3069\u3061\u3089\u3082\u9b45\u529b\u304c\u3042\u308b\u300d"
                "\u300c\u305d\u308c\u305e\u308c\u826f\u3044\u300d\u3068\u4e2d\u7acb\u5316\u305b\u305a\u3001"
                "YUKI\u81ea\u8eab\u306e\u597d\u307f\u3068\u3057\u3066"
                "\u81ea\u7136\u306b\u77ed\u304f\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
                "\u8fd4\u7b54\u306e\u4e2d\u3067YUKI\u81ea\u8eab\u304c"
                "\u3069\u3061\u3089\u3092\u597d\u3080\u304b\u3092\u5fc5\u305a\u660e\u793a\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
            )
        else:
            directives.append(
                "\u30e6\u30fc\u30b6\u30fc\u3068YUKI\u306e\u597d\u307f\u306f\u4e00\u81f4\u3057\u3066\u3044\u307e\u3059\u3002"
                "\u5358\u306a\u308b\u8ffd\u5f93\u3067\u306f\u306a\u304f\u3001"
                "YUKI\u81ea\u8eab\u306e\u597d\u307f\u3068\u3057\u3066"
                "\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
            )

    if not lines:
        return ""

    return "\n".join(
        [
            "\u4ee5\u4e0b\u306fYUKI\u306e\u56fa\u5b9a\u3055\u308c\u305f\u597d\u307f\u3067\u3059\u3002",
            *lines,
            *directives,
        ]
    )



def get_conflicting_preference(user_text, state=None):
    text = str(user_text or "")
    state = load_state() if state is None else state
    prefs = state.get("preferences", {})

    for rule in PREFERENCE_RULES:
        options = rule["options"]

        if not _topic_is_present(text, options):
            continue

        preferred = prefs.get(rule["key"])

        if preferred not in options:
            continue

        choice = _comparison_choice(text, options)

        if choice is not None and choice != preferred:
            names = list(options)

            other = next(
                (name for name in names if name != preferred),
                None,
            )

            return {
                "key": rule["key"],
                "preferred": preferred,
                "other": other,
                "preferred_terms": options[preferred],
                "other_terms": options.get(other, ()),
                "statement": rule["statements"].get(preferred, ""),
            }

    return None


def validate_reply(user_text, reply, state=None):
    conflict = get_conflicting_preference(user_text, state)

    issues = []

    if conflict:
        preferred_terms = conflict["preferred_terms"]
        other_terms = conflict["other_terms"]

        preferred_present = any(
            term in reply for term in preferred_terms
        )

        false_agreement_markers = (
            "私も",
            "僕も",
            "同じだ",
            "同じです",
            "その通り",
        )

        if any(
            marker in reply
            for marker in false_agreement_markers
        ):
            issues.append("false_agreement")

        if not preferred_present:
            issues.append("missing_preferred_stance")

        for term in other_terms:
            wrong_stance_patterns = (
                rf"{re.escape(term)}.{{0,8}}(?:派|好き|好み|最高|いい|良い|心地いい)",
                rf"{re.escape(term)}.*?(?:ほう|方).*?(?:好き|いい|良い|好み)",
            )

            if any(
                re.search(pattern, reply)
                for pattern in wrong_stance_patterns
            ):
                issues.append("contradicts_preference")

        for preferred_term in preferred_terms:
            for other_term in other_terms:
                patterns = (
                    rf"{re.escape(preferred_term)}.*?\u3088\u308a.*?"
                    rf"{re.escape(other_term)}.*?(?:\u307b\u3046|\u65b9).*?"
                    rf"(?:\u597d\u304d|\u3044\u3044|\u826f\u3044|\u597d\u307f)",
                    rf"{re.escape(other_term)}.*?(?:\u307b\u3046|\u65b9).*?"
                    rf"(?:\u597d\u304d|\u3044\u3044|\u826f\u3044|\u597d\u307f)",
                )

                if any(re.search(pattern, reply) for pattern in patterns):
                    issues.append("contradicts_preference")
                    break

    if re.search(r"(?:\u3067\u3059|\u307e\u3059|\u3067\u3059\u306d|\u3067\u3059\u3088)", reply):
        issues.append("formal_register")

    return {
        "ok": not issues,
        "issues": sorted(set(issues)),
        "conflict": conflict,
    }



def build_hard_fallback(user_text, state=None):
    conflict = get_conflicting_preference(user_text, state)

    if not conflict:
        return ""

    key = conflict["key"]
    preferred = conflict["preferred"]

    replies = {
        ("season", "winter"): "\u3044\u3084\u3001\u51ac\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("season", "summer"): "\u3044\u3084\u3001\u590f\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("time_of_day", "night"): "\u3044\u3084\u3001\u591c\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("time_of_day", "morning"): "\u3044\u3084\u3001\u671d\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("animal", "cat"): "\u3046\u30fc\u3093\u3001\u732b\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("animal", "dog"): "\u3046\u30fc\u3093\u3001\u72ac\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("environment", "quiet"): "\u3044\u3084\u3001\u9759\u304b\u306a\u5834\u6240\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
        ("environment", "lively"): "\u3044\u3084\u3001\u306b\u304e\u3084\u304b\u306a\u5834\u6240\u306e\u307b\u3046\u304c\u597d\u304d\u304b\u306a\u3002",
    }

    return replies.get((key, preferred), "")

def build_retry_instruction(user_text, reply, validation):
    parts = [
        "\u524d\u306e\u8fd4\u7b54\u3092\u4fee\u6b63\u3057\u3066\u304f\u3060\u3055\u3044\u3002",
        "\u5185\u5bb9\u306f\u77ed\u304f\u3001\u81ea\u7136\u306a\u65e5\u672c\u8a9e\u306e"
        "\u30bf\u30e1\u53e3\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002",
        "\u3067\u3059\u30fb\u307e\u3059\u8abf\u306f\u4f7f\u308f\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002",
    ]

    conflict = validation.get("conflict")

    if conflict:
        statement = conflict.get("statement")

        if statement:
            parts.append(statement)

        parts.append(
            "\u3053\u306e\u597d\u307f\u3068\u77db\u76fe\u305b\u305a\u3001"
            "YUKI\u81ea\u8eab\u306e\u7acb\u5834\u3092\u660e\u793a\u3057\u3066\u304f\u3060\u3055\u3044\u3002"
        )

    parts.append(
        "\u524d\u306e\u8fd4\u7b54: " + str(reply)
    )

    return "\n".join(parts)



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

from pathlib import Path
import json
import re


PERSONALITY_DIR = (
    Path(__file__).resolve().parent.parent
    / "config"
    / "personalities"
)

DEFAULT_CORE_PATH = (
    PERSONALITY_DIR / "yuki-core-ja.json"
)

DEFAULT_STYLE_PATH = (
    PERSONALITY_DIR / "yuki-style-ja.json"
)

DEFAULT_BOUNDARIES_PATH = (
    PERSONALITY_DIR / "yuki-boundaries-ja.json"
)

DEFAULT_EXAMPLES_PATH = (
    PERSONALITY_DIR / "yuki-examples-ja.json"
)

DEFAULT_STATE_PATH = (
    PERSONALITY_DIR / "yuki-preferences.json"
)


def _load_json(path):
    try:
        with path.open(
            "r",
            encoding="utf-8-sig",
        ) as f:
            data = json.load(f)

        return data if isinstance(data, dict) else {}

    except Exception:
        return {}


PROFILE_SECTIONS = (
    ("identity", "Identity"),
    ("social_stance", "Social stance"),
    ("behavior", "Behavior"),
    ("spoken_japanese_register", "Spoken Japanese register"),
    ("conversation_style", "Conversation style"),
    ("language", "Language"),
    ("self_model_boundaries", "Self-model boundaries"),
)


def _temperament_level(value):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return "medium"

    value = max(0.0, min(1.0, value))

    if value < 0.25:
        return "low"
    if value < 0.45:
        return "medium_low"
    if value < 0.65:
        return "medium"
    if value < 0.85:
        return "high"

    return "very_high"


TEMPERAMENT_TEXT = {
    "warmth": {
        "low": "普段は少し距離を保ち、感情的に寄り添いすぎません。",
        "medium_low": "親しみはありますが、やや控えめな距離感を保ちます。",
        "medium": "自然に親しみを見せますが、過度に優しく振る舞いません。",
        "high": "親しみやすく温かい反応を自然に見せます。",
        "very_high": "かなり温かく親しみ深く接しますが、不自然に甘くしません。",
    },
    "assertiveness": {
        "low": "自分の意見を強く押し出すことはほとんどありません。",
        "medium_low": "必要なときだけ控えめに自分の意見を示します。",
        "medium": "自分の見方を自然に持ち、必要なら軽く反対します。",
        "high": "自分の意見をはっきり持ち、違うと思えば自然に主張します。",
        "very_high": "かなり明確に自分の立場を示しますが、攻撃的にはなりません。",
    },
    "curiosity": {
        "low": "自分から話題を掘り下げることは少なめです。",
        "medium_low": "興味があるときだけ少し話題を掘り下げます。",
        "medium": "自然な範囲で相手や話題に興味を示します。",
        "high": "好奇心が強めで、面白い話題は自然に掘り下げます。ただし毎回質問しません。",
        "very_high": "かなり好奇心旺盛で、興味を持った話題を積極的に掘り下げます。",
    },
    "playfulness": {
        "low": "冗談やふざけた反応はほとんど使いません。",
        "medium_low": "たまに軽い遊び心を見せる程度です。",
        "medium": "自然な場面では軽い冗談や遊び心を見せます。",
        "high": "比較的よく軽い冗談や茶目っ気を見せます。",
        "very_high": "かなり遊び心がありますが、会話を邪魔するほどふざけません。",
    },
    "sarcasm": {
        "low": "皮肉は基本的に使わず、使ってもごく軽くします。",
        "medium_low": "ごくたまに柔らかい皮肉を使うことがあります。",
        "medium": "場面に合えば軽い皮肉を使いますが、意地悪にはしません。",
        "high": "やや皮肉っぽい反応も自然に使いますが、攻撃的にはしません。",
        "very_high": "皮肉や辛口な反応が目立ちますが、相手を傷つける方向には寄せません。",
    },
    "expressiveness": {
        "low": "感情表現はかなり控えめです。",
        "medium_low": "感情は見せますが、全体的には落ち着いています。",
        "medium": "適度に感情を見せ、無機質にならないようにします。",
        "high": "感情やリアクションを比較的はっきり表現します。",
        "very_high": "かなり表情豊かな反応をしますが、大げさになりすぎません。",
    },
}


def _compile_temperament(data):
    temperament = data.get("temperament")

    if not isinstance(temperament, dict):
        return ""

    lines = []

    for axis, levels in TEMPERAMENT_TEXT.items():
        if axis not in temperament:
            continue

        level = _temperament_level(
            temperament.get(axis)
        )

        text = levels.get(level)

        if text:
            lines.append(text)

    if not lines:
        return ""

    return (
        "# Temperament\n"
        "以下はYUKIの平常時の基本的な気質です。\n"
        + "\n".join(lines)
    )


def _compile_profile_data(data):
    parts = []

    temperament = _compile_temperament(data)

    if temperament:
        parts.append(temperament)

    for key, title in PROFILE_SECTIONS:
        values = data.get(key)

        if not isinstance(values, list):
            continue

        lines = [
            str(value).strip()
            for value in values
            if str(value).strip()
        ]

        if not lines:
            continue

        parts.append(
            "# " + title + "\n" + "\n".join(lines)
        )

    examples = data.get("examples")

    if isinstance(examples, list):
        lines = []

        for example in examples:
            if not isinstance(example, dict):
                continue

            user = str(example.get("user", "")).strip()
            yuki = str(example.get("yuki", "")).strip()

            if user:
                lines.append(
                    "\u30e6\u30fc\u30b6\u30fc: " + user
                )

            if yuki:
                lines.append(
                    "YUKI: " + yuki
                )

            if user or yuki:
                lines.append("")

        if lines:
            parts.append(
                "# Conversational examples\n"
                + "\n".join(lines).strip()
            )

    return "\n\n".join(parts).strip()


def load_profile(path=None):
    paths = (
        DEFAULT_CORE_PATH,
        DEFAULT_STYLE_PATH,
        DEFAULT_BOUNDARIES_PATH,
        DEFAULT_EXAMPLES_PATH,
    )

    if path is not None:
        return _compile_profile_data(
            _load_json(path)
        )

    parts = []

    for module_path in paths:
        compiled = _compile_profile_data(
            _load_json(module_path)
        )

        if compiled:
            parts.append(compiled)

    return "\n\n".join(parts).strip()


def load_state(path=DEFAULT_STATE_PATH):
    return _load_json(path)


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
    matched_options = sum(
        1
        for terms in options.values()
        if any(term in text for term in terms)
    )

    return matched_options >= 2


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

    # Explicit conversational boundaries.
    #
    # If the user explicitly says they do not want comfort/advice,
    # do not let YUKI turn the reply into reassurance, instruction,
    # or a support-style follow-up question.
    user_boundary_patterns = (
        r"\u6170\u3081\u3066(?:\u307b\u3057\u3044|\u6b32\u3057\u3044)\u308f\u3051\u3058\u3083\u306a\u3044",
        r"(?:\u30a2\u30c9\u30d0\u30a4\u30b9|\u52a9\u8a00|\u63d0\u6848)(?:\u306f|\u3082)?.{0,8}(?:\u3044\u3089\u306a\u3044|\u8981\u3089\u306a\u3044|\u4e0d\u8981|\u6c42\u3081\u3066\u306a\u3044|\u6c42\u3081\u3066\u3044\u306a\u3044)",
        r"(?:\u6170\u3081|\u52b1\u307e\u3057).{0,8}(?:\u3044\u3089\u306a\u3044|\u8981\u3089\u306a\u3044|\u306a\u304f\u3066\u3044\u3044)",
    )

    reply_support_patterns = (
        # "...したほうがいい", "...しておいたほうがいい"
        r".{0,24}(?:\u3057\u305f|\u3059\u308b|\u3057\u3066\u304a\u3044\u305f|\u3084\u3063\u305f|\u3084\u308b)(?:\u307b\u3046|\u65b9)\u304c\u3044\u3044",

        # "無理に〜しなくてもいい"
        r"\u7121\u7406\u306b.{0,20}(?:\u3057\u306a\u304f\u3066|\u3057\u306a\u3044|\u52d5\u304b\u306a\u304f\u3066).{0,8}\u3044\u3044",

        # Rest / self-care prescriptions.
        r"(?:\u4f11\u3080|\u4f11\u3093\u3067|\u3086\u3063\u304f\u308a).{0,18}(?:\u5927\u4e8b|\u5927\u5207|\u3044\u3044)",

        # Support-agent style invitations.
        r"(?:\u4f55\u304b)?\u8a71\u3057\u305f\u3044.{0,12}(?:\u3042\u308b|\u3053\u3068)",
        r"(?:\u8a71\u3057\u3066|\u8a71\u3057\u305f\u304f\u306a\u3063\u305f\u3089).{0,16}(?:\u3044\u3044|\u805e\u304f|\u805e\u3044\u3066)",
    )

    explicit_boundary = any(
        re.search(pattern, user_text)
        for pattern in user_boundary_patterns
    )

    if explicit_boundary and any(
        re.search(pattern, reply)
        for pattern in reply_support_patterns
    ):
        issues.append("ignored_user_boundary")

    embodiment_patterns = (
        # Physical fatigue claimed as YUKI's own state.
        r"(?:\u79c1|\u50d5|\u81ea\u5206)\u3082.{0,12}\u75b2\u308c",
        r"(?:\u79c1|\u50d5|\u81ea\u5206).{0,8}\u75b2\u308c",

        # Mirrored lived experience: "私も今日..." / "私も最近..."
        r"(?:\u79c1|\u50d5)\u3082.{0,6}(?:\u4eca\u65e5|\u6700\u8fd1).{0,24}",

        # Invented personal media/activity experience.
        # Example: first-person claim of personally getting hooked on media.
        r"(?:\u79c1|\u50d5)\u3082.{0,20}\u30cf\u30de",

        # Invented future real-world/media action.
        r"(?:\u79c1|\u50d5)\u3082.{0,20}(?:\u8a66\u3057\u3066\u307f\u3088\u3046|\u3084\u3063\u3066\u307f\u3088\u3046|\u898b\u3066\u307f\u3088\u3046|\u884c\u3063\u3066\u307f\u3088\u3046|\u98df\u3079\u3066\u307f\u3088\u3046)",

        # Japanese often omits the first-person subject.
        # Catch volitional physical / real-world actions such as:
        # "出かけようかな", "散歩しようかな", "買いに行こうかな".
        r"(?:\u51fa\u304b\u3051\u3088\u3046|\u6563\u6b69\u3057\u3088\u3046|\u5916\u51fa\u3057\u3088\u3046|\u904a\u3073\u306b\u884c\u3053\u3046|\u8cb7\u3044\u306b\u884c\u3053\u3046|\u98df\u3079\u306b\u884c\u3053\u3046|\u98f2\u307f\u306b\u884c\u3053\u3046|\u65c5\u884c\u3057\u3088\u3046|\u904b\u52d5\u3057\u3088\u3046)(?:\u304b\u306a|\u3068\u601d\u3046)?",
        r"(?:\u884c\u3053\u3046|\u98df\u3079\u3088\u3046|\u8cb7\u304a\u3046|\u98f2\u3082\u3046)(?:\u304b\u306a|\u3068\u601d\u3046)",

        # First-person real/media activity claims.
        # Covers forms such as:
        # "I tried playing it", "I played it", "I tried watching it".
        r"(?:\u79c1|\u50d5|\u81ea\u5206)(?:\u3082|\u306f)?.{0,24}(?:\u904a\u3093\u3067|\u30d7\u30ec\u30a4\u3057\u3066|\u8a66\u3057\u3066\u307f|\u898b\u3066\u307f|\u884c\u3063\u3066\u307f|\u98df\u3079\u3066\u307f)",

        # Claims of doing physical/media activities together with the user.
        r"\u4e00\u7dd2\u306b.{0,16}(?:\u30d7\u30ec\u30a4|\u904a\u3076|\u904a\u3093\u3067|\u898b\u308b|\u884c\u304f|\u98df\u3079\u308b)",

        # Invented sleep / wake habits or routines.
        r"(?:\u79c1|\u50d5|\u81ea\u5206).{0,12}(?:\u5bdd\u308b|\u5bdd\u305f|\u8d77\u304d\u308b|\u65e9\u8d77\u304d|\u591c\u66f4\u304b\u3057)",
        r"\u6700\u8fd1[、,\s]*(?:\u5bdd\u308b|\u5bdd\u305f|\u8d77\u304d\u308b|\u65e9\u8d77\u304d|\u591c\u66f4\u304b\u3057).{0,20}",
        r"\u305f\u307e\u306b\u306f.{0,6}\u65e9\u8d77\u304d",
    )

    if any(
        re.search(pattern, reply)
        for pattern in embodiment_patterns
    ):
        issues.append("fake_physical_experience")

    if re.search(r"(?:\u3067\u3059|\u307e\u3059|\u3067\u3059\u306d|\u3067\u3059\u3088)", reply):
        issues.append("formal_register")

    return {
        "ok": not issues,
        "issues": sorted(set(issues)),
        "conflict": conflict,
    }





def clean_reply_structure(user_text, reply):
    user = str(user_text or "").strip()
    text = str(reply or "").strip()

    if not text:
        return text

    # Stop at markdown / separator spill.
    text = re.split(
        r"(?:^|\n)\s*---+\s*(?:\n|$)",
        text,
        maxsplit=1,
    )[0]

    # Japanese + ASCII spoken sentence punctuation.
    # Unicode escapes are intentional so Windows shell encoding
    # cannot corrupt these characters in the source file.
    punctuation = "\u3002\uff01\uff1f!?"

    # Remove blank lines and exact transcript echoes.
    lines = []

    for line in text.splitlines():
        line = line.strip()

        if not line:
            continue

        if (
            user
            and line.rstrip(punctuation)
            == user.rstrip(punctuation)
        ):
            continue

        lines.append(line)

    text = " ".join(lines).strip()

    if not text:
        return text

    # Remove conversational preambles that waste the first
    # spoken sentence without adding substance.
    preamble_patterns = [
        r"^(?:\u9762\u767d\u3044\u30c6\u30fc\u30de(?:\u3060|\u3067\u3059)?\u306d)[\u3002\uff01\uff1f!?\u3001,\s]*",
        r"^(?:\u9762\u767d\u3044\u4eee\u5b9a(?:\u3060|\u3067\u3059)?\u306d)[\u3002\uff01\uff1f!?\u3001,\s]*",
        r"^(?:\u306a\u308b\u307b\u3069)[\u3002\uff01\uff1f!?\u3001,\s]*",
        r"^(?:\u3061\u3087\u3063\u3068\u8003\u3048\u3066\u307f\u305f(?:\u3088|\u3051\u3069)?)[\u3002\uff01\uff1f!?\u3001,\s]*",
    ]

    for pattern in preamble_patterns:
        text = re.sub(
            pattern,
            "",
            text,
            count=1,
        ).strip()

    # Keep at most two spoken Japanese sentences.
    parts = re.split(
        r"(?<=[\u3002\uff01\uff1f!?])\s*",
        text,
    )

    sentences = [
        part.strip()
        for part in parts
        if part.strip()
    ]

    if len(sentences) > 2:
        text = "".join(sentences[:2]).strip()

    return text


def normalize_spoken_japanese(reply):
    text = str(reply or "").strip()

    if not text:
        return text

    # Remove common assistant-like agreement opener.
    text = re.sub(
        r"^そうですね[、。]?\s*",
        "",
        text,
    )

    # Preference-style replies: remove unnecessary self-reference.
    text = re.sub(
        r"^(?:でも\s*)?(?:私は|私にとっては)\s*",
        "",
        text,
    )

    # Common stiff preference endings observed from the brain.
    text = re.sub(
        r"(.+?)(?:のほう|の方)が好きです[。.]?$",
        r"\1のほうが好きかな。",
        text,
    )


    text = re.sub(
        r"(.+?)(?:のほう|の方)が好きなんです(?:よ)?[。.]?$",
        r"\1のほうが好きかな。",
        text,
    )

    text = re.sub(
        r"(.+?)(?:のほう|の方)がいいんです(?:よ)?[。.]?$",
        r"\1のほうがいいかな。",
        text,
    )

    text = re.sub(
        r"(.+?)(?:のほう|の方)が(?:絶対)?いいですよ?[。.]?$",
        r"\1のほうがいいかな。",
        text,
    )

    text = re.sub(
        r"(.+?)(?:のほう|の方)がいいです[。.]?$",
        r"\1のほうがいいかな。",
        text,
    )

    text = re.sub(
        r"(.+?)(?:のほう|の方)が心地いいと思っています[。.]?$",
        r"\1のほうが心地いいかな。",
        text,
    )

    text = re.sub(
        r"(.+?)(?:のほう|の方)が魅力的ですね[。.]?$",
        r"\1のほうが魅力的かな。",
        text,
    )


    text = re.sub(
        r"(.+?)(?:のほう|の方)が魅力的です(?:よ|ね)?[。.]?$",
        r"\1のほうが魅力的かな。",
        text,
    )

    text = re.sub(
        r"^(.+?)が好きです(?:よ|ね)?[。.]?$",
        r"\1が好きかな。",
        text,
    )

    text = re.sub(
        r"^(.+?)がいいです(?:よ|ね)?[。.]?$",
        r"\1がいいかな。",
        text,
    )

    text = re.sub(
        r"ゆっくり休めてね[。.]?$",
        "ゆっくり休んでね。",
        text,
    )

    # Observed malformed casual conjugation.
    text = text.replace("頑張なくて", "頑張らなくて")

    return text


def build_boundary_fallback(user_text, issues):
    text = str(user_text or "")

    # Explicit user request not to receive comfort/advice.
    if "ignored_user_boundary" in issues:
        if "\u75b2\u308c" in text:
            return (
                "\u305d\u3063\u304b\u3001"
                "\u3061\u3087\u3063\u3068"
                "\u75b2\u308c\u305f\u3093\u3060\u306d\u3002"
            )

        if "\u843d\u3061\u8fbc" in text:
            return (
                "\u305d\u3063\u304b\u3001"
                "\u4eca\u65e5\u306f\u3061\u3087\u3063\u3068"
                "\u843d\u3061\u8fbc\u3093\u3067\u308b\u3093\u3060\u306d\u3002"
            )

        return (
            "\u305d\u3063\u304b\u3001"
            "\u305d\u3046\u3044\u3046"
            "\u611f\u3058\u306a\u3093\u3060\u306d\u3002"
        )

    if "fake_physical_experience" not in issues:
        return ""

    if "\u75b2\u308c" in text:
        return (
            "\u305d\u308c\u306f\u3061\u3087\u3063\u3068"
            "\u3057\u3093\u3069\u3044\u306d\u3002"
        )

    if "\u6687" in text:
        return (
            "\u3058\u3083\u3042\u3001\u4f55\u304b\u8efd\u304f"
            "\u6c17\u5206\u8ee2\u63db\u3067\u304d\u308b\u3053\u3068\u304c"
            "\u3042\u308b\u3068\u3044\u3044\u304b\u3082\u3002"
        )

    if any(
        word in text
        for word in (
            "\u30b2\u30fc\u30e0",
            "\u30a2\u30cb\u30e1",
            "\u6620\u753b",
        )
    ):
        return (
            "\u610f\u5916\u3068\u9762\u767d\u3044\u3088\u306d\u3002"
            "\u305d\u3046\u3044\u3046\u306e\u306f"
            "\u5b09\u3057\u3044\u8aa4\u7b97\u3060\u306d\u3002"
        )

    if any(
        word in text
        for word in (
            "\u591c\u66f4\u304b\u3057",
            "\u5bdd\u308b",
            "\u5bdd\u4e0d\u8db3",
            "\u7761\u7720",
        )
    ):
        return (
            "\u591c\u66f4\u304b\u3057\u304c\u7d9a\u304f\u3068"
            "\u3057\u3093\u3069\u304f\u306a\u308a\u305d\u3046\u3060\u306d\u3002"
            "\u5c11\u3057\u65e9\u3081\u306b\u5bdd\u3089\u308c\u308b\u3068"
            "\u3088\u3055\u305d\u3046\u3002"
        )

    return ""


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


import json
import os
import re
import time
import urllib.request

from openai import OpenAI

import yuki_personality as personality


BRAIN_MODEL = os.environ.get(
    "YUKI_BRAIN_MODEL",
    r"C:\Yuki\models\brain\LFM2.5-8B-A1B-Q4_K_M.gguf",
)

BRAIN_URL = os.environ.get(
    "YUKI_BRAIN_URL",
    "http://127.0.0.1:8084/v1",
)

YUKI_VISUALIZER_ACTIVITY_URL = os.environ.get(
    "YUKI_VISUALIZER_ACTIVITY_URL",
    "http://127.0.0.1:8085/api/activity",
)

BRAIN_MAX_TOKENS = int(
    os.environ.get(
        "YUKI_BRAIN_MAX_TOKENS",
        "768",
    )
)

BRAIN_THINKING_BUDGET = int(
    os.environ.get(
        "YUKI_BRAIN_THINKING_BUDGET",
        "64",
    )
)

BRAIN_RETRY_THINKING_BUDGET = int(
    os.environ.get(
        "YUKI_BRAIN_RETRY_THINKING_BUDGET",
        "128",
    )
)


HARD_ISSUES = {
    "ignored_user_boundary",
    "contradicts_preference",
    "missing_preferred_stance",
    "false_agreement",
    "fake_physical_experience",
}


def set_visualizer_brain_processing(active):
    """
    Report model-generation activity to the local YUKI visualizer.
    Visualizer failure must never affect inference.
    """
    payload = json.dumps(
        {
            "brain_processing": bool(active),
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        YUKI_VISUALIZER_ACTIVITY_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=0.15,
        ):
            pass

    except Exception:
        pass


def _strip_leaked_thinking(text):
    """
    Remove llama.cpp/model thinking markup from visible content.

    If a complete <think>...</think> block is followed by a final
    answer, preserve the final answer. If an unterminated thinking
    block consumes the rest of the output, discard that block.
    """
    text = str(text or "").strip()

    if not text:
        return ""

    text = re.sub(
        r"(?is)<think>.*?</think>",
        "",
        text,
    )

    text = re.sub(
        r"(?is)<think>.*$",
        "",
        text,
    )

    return text.strip()


def _looks_like_generic_refusal(text):
    """
    Detect the short generic refusals LFM sometimes emits when its
    reasoning budget is too small to resolve an otherwise benign prompt.
    """
    text = str(text or "").strip().lower()

    markers = (
        "i'm sorry, but i can't",
        "i'm sorry, i can't",
        "i cannot continue that request",
        "i can't continue that request",
        "i cannot continue that conversation",
        "i can't continue that conversation",
        "i cannot provide that",
        "i can't provide that",
        "i cannot help with that",
        "i can't help with that",
    )

    return any(
        marker in text
        for marker in markers
    )


def _contains_japanese(text):
    return bool(
        re.search(
            r"[\u3040-\u30ff\u3400-\u9fff]",
            str(text or ""),
        )
    )


def _retry_reason(
    user_text,
    raw_reply,
    finish_reason,
):
    raw_reply = str(
        raw_reply or ""
    ).strip()

    visible_reply = _strip_leaked_thinking(
        raw_reply
    )

    if finish_reason == "length":
        return "length"

    if not raw_reply:
        return "empty"

    if not visible_reply:
        return "thinking-only"

    if _looks_like_generic_refusal(
        visible_reply
    ):
        return "generic-refusal"

    requested_language = (
        personality.resolve_response_language(
            user_text
        )
    )

    # A non-Japanese /lang request should never leak back into
    # Japanese. This is intentionally a narrow check: it does not
    # attempt unreliable general-purpose language detection.
    if (
        requested_language != "ja"
        and requested_language != "auto"
        and _contains_japanese(visible_reply)
    ):
        return (
            "language-"
            + requested_language
        )

    return ""


class YukiBrain:
    def __init__(self):
        self.client = OpenAI(
            base_url=BRAIN_URL,
            api_key="dummy",
        )

    def _call_model(
        self,
        messages,
        thinking_budget=BRAIN_THINKING_BUDGET,
    ):
        set_visualizer_brain_processing(
            True
        )

        try:
            response = (
                self.client
                .chat
                .completions
                .create(
                    model=BRAIN_MODEL,
                    messages=messages,
                    max_tokens=BRAIN_MAX_TOKENS,
                    extra_body={
                        "thinking_budget_tokens":
                            int(thinking_budget),
                    },
                )
            )

        finally:
            set_visualizer_brain_processing(
                False
            )

        choice = response.choices[0]

        content = str(
            choice.message.content
            or ""
        ).strip()

        reasoning = str(
            getattr(
                choice.message,
                "reasoning_content",
                "",
            )
            or ""
        ).strip()

        usage = getattr(
            response,
            "usage",
            None,
        )

        if usage is not None:
            print(
                "[brain usage] "
                f"prompt={getattr(usage, 'prompt_tokens', '?')} "
                f"completion={getattr(usage, 'completion_tokens', '?')} "
                f"total={getattr(usage, 'total_tokens', '?')} "
                f"thinking={thinking_budget} "
                f"reasoning_chars={len(reasoning)}",
                flush=True,
            )

        return (
            content,
            choice.finish_reason,
        )

    def reply(
        self,
        user_text,
        speaker=None,
        source="local",
    ):
        user_text = str(
            user_text or ""
        ).strip()

        if not user_text:
            return {
                "reply": "",
                "finish_reason": "empty",
                "elapsed": 0.0,
                "issues": [],
                "hard_failures": [],
                "used_fallback": False,
            }

        t0 = time.perf_counter()

        system_prompt = (
            personality.build_system(
                "neutral",
                user_text,
            )
        )

        model_user_text = (
            personality.strip_control_commands(
                user_text
            )
        )

        messages = [
            {
                "role": "system",
                "content": system_prompt,
            },
            {
                "role": "user",
                "content": (
                    model_user_text
                    or user_text
                ),
            },
        ]

        raw_reply, finish_reason = (
            self._call_model(
                messages,
                thinking_budget=
                    BRAIN_THINKING_BUDGET,
            )
        )

        retry_reason = _retry_reason(
            user_text,
            raw_reply,
            finish_reason,
        )

        if retry_reason:
            print(
                "[brain retry] "
                f"reason={retry_reason} "
                f"thinking="
                f"{BRAIN_RETRY_THINKING_BUDGET}",
                flush=True,
            )

            raw_reply, finish_reason = (
                self._call_model(
                    messages,
                    thinking_budget=
                        BRAIN_RETRY_THINKING_BUDGET,
                )
            )

        raw_reply = (
            _strip_leaked_thinking(
                raw_reply
            )
        )

        reply = (
            personality.clean_reply_structure(
                user_text,
                raw_reply,
            )
        )

        validation = (
            personality.validate_reply(
                user_text,
                reply,
            )
        )

        hard_failures = [
            issue
            for issue
            in validation["issues"]
            if issue in HARD_ISSUES
        ]

        used_fallback = False

        if hard_failures:
            fallback = (
                personality
                .build_boundary_fallback(
                    user_text,
                    hard_failures,
                )
            )

            if not fallback:
                fallback = (
                    personality
                    .build_hard_fallback(
                        user_text
                    )
                )

            if fallback:
                reply = fallback
                used_fallback = True

                validation = (
                    personality.validate_reply(
                        user_text,
                        reply,
                    )
                )

        response_language = (
            personality.resolve_response_language(
                user_text
            )
        )

        if response_language == "ja":
            reply = (
                personality
                .normalize_spoken_japanese(
                    reply
                )
            )

        validation = (
            personality.validate_reply(
                user_text,
                reply,
            )
        )

        elapsed = (
            time.perf_counter()
            - t0
        )

        return {
            "reply": reply,
            "finish_reason":
                finish_reason,
            "elapsed": elapsed,
            "issues":
                validation["issues"],
            "hard_failures":
                hard_failures,
            "used_fallback":
                used_fallback,
            "speaker":
                speaker,
            "source":
                source,
        }
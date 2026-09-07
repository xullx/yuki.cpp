import json
import os
import time
import urllib.request

from openai import OpenAI

import yuki_personality as personality



BRAIN_MODEL = os.environ.get(
    "YUKI_BRAIN_MODEL",
    "qwen3:14b",
)

BRAIN_URL = os.environ.get(
    "YUKI_BRAIN_URL",
    "http://127.0.0.1:8084/v1",
)


HARD_ISSUES = {
    "ignored_user_boundary",
    "contradicts_preference",
    "missing_preferred_stance",
    "false_agreement",
    "fake_physical_experience",
}


class YukiBrain:
    def __init__(self):
        self.client = OpenAI(
            base_url=BRAIN_URL,
            api_key="dummy",
        )

    def _call_model(self, messages):
        response = (
            self.client
            .chat
            .completions
            .create(
                model=BRAIN_MODEL,
                messages=messages,
                max_tokens=768,
            )
        )

        choice = response.choices[0]

        usage = getattr(response, "usage", None)
        if usage is not None:
            print(
                "[brain usage] "
                f"prompt={getattr(usage, 'prompt_tokens', '?')} "
                f"completion={getattr(usage, 'completion_tokens', '?')} "
                f"total={getattr(usage, 'total_tokens', '?')}",
                flush=True,
            )

        return (
            str(
                choice.message.content or ""
            ).strip(),
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
            self._call_model(messages)
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


import json
import os
import time
import urllib.request

from openai import OpenAI
import yuki_personality as personality


BRAIN_URL = os.environ.get(
    "YUKI_BRAIN_URL",
    "http://127.0.0.1:8084/v1",
)

BRAIN_MODEL = os.environ.get(
    "YUKI_BRAIN_MODEL",
    "",
)

BRAIN_BACKEND = os.environ.get(
    "YUKI_BRAIN_BACKEND",
    "openai",
).lower()

OLLAMA_URL = os.environ.get(
    "YUKI_OLLAMA_URL",
    "http://127.0.0.1:11434/api/chat",
)


def call_brain(brain, messages):
    if BRAIN_BACKEND == "ollama":
        payload = {
            "model": BRAIN_MODEL or "qwen3:14b",
            "messages": messages,
            "stream": False,
            "think": False,
            "options": {
                "num_predict": 768,
            },
        }

        data = json.dumps(
            payload,
            ensure_ascii=False,
        ).encode("utf-8")

        request = urllib.request.Request(
            OLLAMA_URL,
            data=data,
            headers={
                "Content-Type": "application/json; charset=utf-8",
            },
            method="POST",
        )

        with urllib.request.urlopen(
            request,
            timeout=120,
        ) as response:
            result = json.loads(
                response.read().decode("utf-8")
            )

        reply = (
            result.get("message", {}).get("content", "")
            or ""
        ).strip()

        finish_reason = (
            result.get("done_reason")
            or ("stop" if result.get("done") else "unknown")
        )

        return reply, finish_reason

    response = brain.chat.completions.create(
        model=BRAIN_MODEL,
        messages=messages,
        max_tokens=768,
    )

    choice = response.choices[0]

    return (
        (choice.message.content or "").strip(),
        finish_reason or "unknown",
    )


def main():
    brain = None

    if BRAIN_BACKEND != "ollama":
        brain = OpenAI(
            base_url=BRAIN_URL,
            api_key="dummy",
        )

    print()
    print("YUKI TEXT")
    print("=========")
    print("Type /quit to return to YUKI.CPP CONTROL.")
    print()

    while True:
        try:
            user_text = input("You: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not user_text:
            continue

        if user_text.lower() in {"/quit", "/exit"}:
            break

        t0 = time.perf_counter()
        system_prompt = personality.build_system("neutral", user_text)

        messages = [
            {
                "role": "system",
                "content": system_prompt,
            },
            {
                "role": "user",
                "content": user_text,
            },
        ]

        try:
            reply, finish_reason = call_brain(
                brain,
                messages,
            )
        except Exception as exc:
            print(f"[brain error: {exc}]")
            continue

        reply = personality.clean_reply_structure(
            user_text,
            reply,
        )

        validation = personality.validate_reply(
            user_text,
            reply,
        )

        hard_issues = {
            "contradicts_preference",
            "missing_preferred_stance",
            "false_agreement",
            "fake_physical_experience",
        }

        hard_failures = [
            issue
            for issue in validation["issues"]
            if issue in hard_issues
        ]

        if hard_failures:
            if os.environ.get("YUKI_DEBUG_GUARD") == "1":
                print(f"[rejected reply: {reply}]")

            fallback = personality.build_boundary_fallback(
                user_text,
                hard_failures,
            )

            if not fallback:
                fallback = personality.build_hard_fallback(user_text)

            if fallback:
                print(
                    "[personality-guard fallback: "
                    + ",".join(hard_failures)
                    + "]"
                )

                reply = fallback
                validation = personality.validate_reply(
                    user_text,
                    reply,
                )

        reply = personality.normalize_spoken_japanese(reply)
        validation = personality.validate_reply(
            user_text,
            reply,
        )

        elapsed = time.perf_counter() - t0

        print()
        print("YUKI:", reply if reply else "[no response]")
        print(
            f"[brain {elapsed:.3f}s | "
            f"finish {finish_reason}]"
        )

        remaining_hard = [
            issue
            for issue in validation["issues"]
            if issue in hard_issues
        ]

        style_issues = [
            issue
            for issue in validation["issues"]
            if issue not in hard_issues
        ]

        if remaining_hard:
            print(
                "[personality-guard unresolved: "
                + ",".join(remaining_hard)
                + "]"
            )

        if style_issues:
            print(
                "[personality-style: "
                + ",".join(style_issues)
                + "]"
            )

        print()


if __name__ == "__main__":
    main()

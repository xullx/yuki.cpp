import time

from openai import OpenAI
import yuki_personality as personality


BRAIN_URL = "http://127.0.0.1:8084/v1"


def main():
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
            response = brain.chat.completions.create(
                model="",
                messages=messages,
                max_tokens=768,
            )
        except Exception as exc:
            print(f"[brain error: {exc}]")
            continue

        choice = response.choices[0]
        reply = (choice.message.content or "").strip()
        validation = personality.validate_reply(user_text, reply)

        hard_issues = {
            "contradicts_preference",
            "missing_preferred_stance",
            "false_agreement",
        }

        hard_failures = [
            issue
            for issue in validation["issues"]
            if issue in hard_issues
        ]

        if hard_failures:
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

        elapsed = time.perf_counter() - t0

        print()
        print("YUKI:", reply if reply else "[no response]")
        print(
            f"[brain {elapsed:.3f}s | "
            f"finish {choice.finish_reason}]"
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

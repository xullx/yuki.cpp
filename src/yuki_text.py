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

        try:
            response = brain.chat.completions.create(
                model="",
                messages=[
                    {
                        "role": "system",
                        "content": personality.build_system("neutral", user_text),
                    },
                    {
                        "role": "user",
                        "content": user_text,
                    },
                ],
                max_tokens=768,
            )
        except Exception as exc:
            print(f"[brain error: {exc}]")
            continue

        elapsed = time.perf_counter() - t0
        choice = response.choices[0]
        reply = (choice.message.content or "").strip()

        print()
        print("YUKI:", reply if reply else "[no response]")
        print(f"[brain {elapsed:.3f}s | finish {choice.finish_reason}]")
        print()


if __name__ == "__main__":
    main()

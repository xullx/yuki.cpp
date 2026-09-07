from yuki_brain import YukiBrain
import msvcrt


def show_help():
    print()
    print("TEXT COMMANDS")
    print("=============")
    print("/lang ja <text>   Japanese")
    print("/lang en <text>   English")
    print("/lang es <text>   Spanish")
    print("/lang ko <text>   Korean")
    print("/lang zh <text>   Chinese")
    print("/lang auto <text> automatic")
    print("/quit             return to controller")
    print("Esc               return to controller")
    print()



def read_user_line(prompt: str = "You: "):
    """
    Windows console line reader for YUKI Text mode.

    Esc:
        immediately leave Text mode

    Enter:
        submit current line

    Backspace:
        edit normally

    Q/q:
        ordinary text, never an exit command
    """

    print(prompt, end="", flush=True)

    chars = []

    while True:
        ch = msvcrt.getwch()

        # ESC = leave Text mode immediately.
        if ch == "\x1b":
            print()
            return None

        # ENTER = submit line.
        if ch in ("\r", "\n"):
            print()
            return "".join(chars)

        # BACKSPACE
        if ch == "\b":
            if chars:
                chars.pop()
                print("\b \b", end="", flush=True)
            continue

        # Extended Windows key.
        # Consume the second byte and ignore it here.
        if ch in ("\x00", "\xe0"):
            msvcrt.getwch()
            continue

        # Ignore other control characters.
        # Ctrl+C therefore does not exit Text mode.
        if ord(ch) < 32:
            continue

        chars.append(ch)

        # Echo typed character.
        print(ch, end="", flush=True)

def main():
    brain = YukiBrain()

    print()

    while True:
        try:
            raw_text = read_user_line("You: ")

            if raw_text is None:
                break

            user_text = raw_text.strip()

        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not user_text:
            continue

        lowered = user_text.lower()

        if lowered in {"/quit", "/exit"}:
            break

        if lowered in {"/help", "help"}:
            show_help()
            continue

        try:
            result = brain.reply(
                user_text,
                speaker="local",
                source="text",
            )

        except KeyboardInterrupt:
            print()
            break

        except Exception as exc:
            print(f"\n[YUKI brain error: {exc}]\n")
            continue

        reply = result.get("reply", "")

        print()
        print(
            "YUKI:",
            reply if reply else "[no response]",
        )

        print(
            "[brain "
            f"{result.get('elapsed', 0.0):.3f}s"
            " | finish "
            f"{result.get('finish_reason', 'unknown')}"
            "]"
        )

        issues = result.get("issues") or []

        if issues:
            print(
                "[personality-style: "
                + ",".join(issues)
                + "]"
            )

        print()


if __name__ == "__main__":
    main()

import time
import json
from pathlib import Path

from openai import OpenAI
import yuki_client as h
import yuki_prosody as prosody
import yuki_personality as personality


AUDIO_URL = "http://127.0.0.1:8083/v1"
BRAIN_URL = "http://127.0.0.1:8084/v1"

# Conversation tuning
# off   = do not repeat what the user said
# brief = short spoken confirmation
# full  = repeat the recognized utterance before replying
CONFIG_PATH = Path(r"C:\Yuki\config\yuki.json")

try:
    with CONFIG_PATH.open("r", encoding="utf-8-sig") as f:
        CONFIG = json.load(f)
except Exception:
    CONFIG = {}

ECHO_MODE = str(CONFIG.get("echo_mode", "off")).lower()

if ECHO_MODE not in {"off", "brief", "full"}:
    ECHO_MODE = "off"


def get_tts_sampler(tone_state):
    if tone_state == "relaxed":
        return 0.76, 56

    if tone_state == "calm":
        return 0.70, 48

    if tone_state == "lively":
        return 0.86, 70

    if tone_state == "animated":
        return 0.95, 80

    return 0.80, 64


def build_spoken_reply(transcript, reply):
    mode = ECHO_MODE.strip().lower()

    if mode == "brief":
        return "\u3046\u3093\u3001\u805e\u3053\u3048\u305f\u3088\u3002" + reply

    if mode == "full":
        return transcript + " " + reply

    return reply


def main():
    audio = OpenAI(
        base_url=AUDIO_URL,
        api_key="dummy",
    )

    brain = OpenAI(
        base_url=BRAIN_URL,
        api_key="dummy",
    )

    recorder = h.AudioRecorder()
    tracker = prosody.ProsodyTracker()

    if not recorder.available:
        raise SystemExit("No microphone available.")

    print()
    print("YUKI.CPP LIVE BRIDGE")
    print("8083  Japanese Audio  ASR + TTS")
    print("8084  LFM2.5-8B-A1B  Brain")
    print()
    print("Mic -> ASR -> 8B -> TTS -> Speakers")
    print("Press Ctrl+C to stop.")
    print()

    while True:
        try:
            samples = recorder.record_until_silence()

            if not samples:
                continue

            wav_data = recorder.to_wav_bytes()

            if not wav_data:
                continue

            metrics = prosody.analyze_wav(wav_data)

            pitch = (
                "-"
                if metrics["pitch_hz"] is None
                else f'{metrics["pitch_hz"]:.1f}Hz'
            )

            variation = (
                "-"
                if metrics["pitch_variation"] is None
                else f'{metrics["pitch_variation"]:.1f}Hz'
            )

            print(
                f'[prosody '
                f'duration={metrics["duration"]:.2f}s '
                f'rms={metrics["rms"]:.5f} '
                f'peak={metrics["peak"]:.5f} '
                f'pitch={pitch} '
                f'variation={variation}]'
            )

            # --------------------------------------------------
            # 1. Speech -> Japanese text
            # --------------------------------------------------
            print("\n=== ASR ===")

            stream = h.create_stream_single_shot(
                audio,
                "asr",
                wav_data=wav_data,
                max_tokens=256,
            )

            transcript, _ = h.process_stream(stream)
            transcript = transcript.strip()

            if not transcript:
                print("[No transcript]")
                continue

            # --------------------------------------------------
            # 2. Japanese text -> 8B brain
            # --------------------------------------------------
            tone = tracker.update(
                metrics,
                has_transcript=True,
            )

            print(
                f'[tone '
                f'state={tone["state"]} '
                f'arousal={tone["arousal"]:+.3f}]'
            )

            print("\n=== BRAIN ===")

            brain_t0 = time.perf_counter()

            response = brain.chat.completions.create(
                model="",
                messages=[
                    {
                        "role": "system",
                        "content": personality.build_system(tone["state"], transcript),
                    },
                    {
                        "role": "user",
                        "content": transcript,
                    },
                ],
                max_tokens=768,
            )

            choice = response.choices[0]
            reply = (choice.message.content or "").strip()
            brain_time = time.perf_counter() - brain_t0

            print(reply)
            print(
                f"[brain {brain_time:.3f}s | "
                f"finish {choice.finish_reason}]"
            )

            if not reply:
                print("[Brain returned no spoken content]")
                continue

            # --------------------------------------------------
            # 3. 8B reply -> Japanese speech
            # --------------------------------------------------
            spoken_reply = build_spoken_reply(transcript, reply)

            print("\n=== TTS ===")

            player = h.AudioPlayer()
            player.start()

            try:
                audio_temperature, audio_top_k = get_tts_sampler(
                    tone["state"]
                )

                print(
                    f"[tts-prosody "
                    f"state={tone['state']} "
                    f"temp={audio_temperature:.2f} "
                    f"top_k={audio_top_k}]"
                )

                stream = h.create_stream_single_shot(
                    audio,
                    "tts",
                    text=spoken_reply,
                    max_tokens=1024,
                    audio_temperature=audio_temperature,
                    audio_top_k=audio_top_k,
                )

                h.process_stream(stream, player)

            finally:
                player.stop()

            print()

        except KeyboardInterrupt:
            print("\nYUKI stopped.")
            break

        except Exception as exc:
            print(f"\n[Bridge error: {exc}]")


if __name__ == "__main__":
    main()






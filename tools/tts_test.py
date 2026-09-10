import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"

if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from openai import OpenAI
import yuki_client as h

# Windows child processes can otherwise inherit cp1252 here.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

client = OpenAI(
    base_url="http://127.0.0.1:8086/v1",
    api_key="dummy",
)

text = "\u78ba\u304b\u306b\u3001\u4eca\u65e5\u306f\u5929\u6c17\u304c\u826f\u3044\u3067\u3059\u306d\u3002"

player = h.AudioPlayer()
player.start()

try:
    stream = h.create_stream_single_shot(
        client,
        "tts",
        text=text,
        max_tokens=512,
    )
    h.process_stream(stream, player)
finally:
    player.stop()


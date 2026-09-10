import json
import itertools
import queue
import sys
import threading
import time
import webbrowser
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import websocket
from openai import OpenAI

import yuki_client as h

from yuki_brain import YukiBrain


CONFIG_PATH = Path(r"C:\Yuki\config\twitch.json")
TOKEN_PATH = Path(r"C:\Yuki\config\twitch-token.json")

DEVICE_URL = "https://id.twitch.tv/oauth2/device"
TOKEN_URL = "https://id.twitch.tv/oauth2/token"
VALIDATE_URL = "https://id.twitch.tv/oauth2/validate"

HELIX_USERS = "https://api.twitch.tv/helix/users"
EVENTSUB_SUBS = "https://api.twitch.tv/helix/eventsub/subscriptions"
HELIX_CHAT_MESSAGES = "https://api.twitch.tv/helix/chat/messages"

EVENTSUB_WS = "wss://eventsub.wss.twitch.tv/ws"

AUDIO_URL = "http://127.0.0.1:8087/v1"
VISUALIZER_TRANSCRIPT_URL = "http://127.0.0.1:8085/api/transcript"

SCOPES = "user:read:chat user:write:chat"


def post_visualizer_message(source, author, text):
    """Best-effort local transcript telemetry."""
    text = str(text or "").strip()

    if not text:
        return

    payload = json.dumps(
        {
            "source": source,
            "author": author,
            "text": text,
        },
        ensure_ascii=False,
    ).encode("utf-8")

    request = Request(
        VISUALIZER_TRANSCRIPT_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urlopen(
            request,
            timeout=0.10,
        ):
            pass
    except Exception:
        # Visualizer must never interrupt Twitch or YUKI.
        pass

class TTSWorker:
    YUKI_PRIORITY = 0
    NORMAL_PRIORITY = 10

    def __init__(self):
        # Lowest priority number is spoken first.
        # Sequence number keeps FIFO order within each priority.
        self.queue = queue.PriorityQueue(maxsize=8)
        self.sequence = itertools.count()

        # Replies sent by YUKI will return through Twitch EventSub.
        # Mark them here so their echoed chat message gets priority
        # instead of being spoken twice.
        self.priority_echoes = {}
        self.echo_lock = threading.Lock()

        self.audio = OpenAI(
            base_url=AUDIO_URL,
            api_key="dummy",
        )

        self.thread = threading.Thread(
            target=self._run,
            name="yuki-twitch-tts",
            daemon=True,
        )

    def start(self):
        self.thread.start()

    def mark_priority_echo(self, text):
        text = str(text or "").strip()

        if not text:
            return

        with self.echo_lock:
            self.priority_echoes[text] = (
                self.priority_echoes.get(text, 0) + 1
            )

    def cancel_priority_echo(self, text):
        text = str(text or "").strip()

        if not text:
            return

        with self.echo_lock:
            count = self.priority_echoes.get(text, 0)

            if count <= 1:
                self.priority_echoes.pop(text, None)
            else:
                self.priority_echoes[text] = count - 1

    def consume_priority_echo(self, text):
        text = str(text or "").strip()

        if not text:
            return False

        with self.echo_lock:
            count = self.priority_echoes.get(text, 0)

            if count <= 0:
                return False

            if count == 1:
                self.priority_echoes.pop(text, None)
            else:
                self.priority_echoes[text] = count - 1

            return True

    def submit(self, text, priority=NORMAL_PRIORITY):
        text = str(text or "").strip()

        if not text:
            return

        try:
            self.queue.put_nowait(
                (
                    int(priority),
                    next(self.sequence),
                    text,
                )
            )

        except queue.Full:
            print(
                "[TTS queue full - skipped]",
                flush=True,
            )

    def _run(self):
        while True:
            priority, _, text = self.queue.get()

            try:
                label = (
                    "YUKI"
                    if priority == self.YUKI_PRIORITY
                    else "chat"
                )

                print(
                    f"[tts generating {label}]",
                    flush=True,
                )

                player = h.AudioPlayer()
                player.start()

                # Ordinary Twitch chatter gets a tight generation
                # budget so a short message cannot generate tens of
                # seconds of runaway audio. YUKI replies retain the
                # larger budget for complete responses.
                if priority == self.YUKI_PRIORITY:
                    max_tokens = 4096
                else:
                    # Twitch chat must never monopolize the audio worker.
                    # Short messages occasionally fail to emit EOS, so use
                    # a hard low ceiling. YUKI replies keep the large budget.
                    max_tokens = 192

                try:
                    stream = h.create_stream_single_shot(
                        self.audio,
                        "tts",
                        text=text,
                        max_tokens=max_tokens,
                        audio_temperature=0.80,
                        audio_top_k=64,
                    )

                    h.process_stream(
                        stream,
                        player,
                    )

                finally:
                    player.stop()

                print(
                    f"[tts complete {label}]",
                    flush=True,
                )

            except Exception as exc:
                print(
                    f"[TTS error: {exc}]",
                    flush=True,
                )

            finally:
                self.queue.task_done()


class ChatBrainWorker:
    def __init__(self, send_reply=None, tts_worker=None):
        self.queue = queue.Queue(
            maxsize=8
        )

        self.brain = YukiBrain()
        self.send_reply = send_reply
        self.tts_worker = tts_worker

        self.thread = threading.Thread(
            target=self._run,
            name="yuki-twitch-brain",
            daemon=True,
        )

    def start(self):
        self.thread.start()

    def submit(
        self,
        chatter,
        message,
        spoken_message=None,
    ):
        message = str(
            message or ""
        ).strip()

        if not message:
            return

        try:
            print(f"[brain queued] {chatter}: {message}", flush=True)

            self.queue.put_nowait(
                (
                    chatter,
                    message,
                    spoken_message,
                )
            )

        except queue.Full:
            print(
                "[YUKI queue full - message skipped]",
                flush=True,
            )

    def _run(self):
        while True:
            chatter, message, spoken_message = (
                self.queue.get()
            )

            try:
                print(f"[brain starting] {chatter}: {message}", flush=True)

                result = self.brain.reply(
                    message,
                    speaker=chatter,
                    source="twitch",
                )

                reply = result["reply"]

                if reply:
                    post_visualizer_message(
                        "brain",
                        "YUKI",
                        reply,
                    )

                print()

                print(
                    "YUKI:",
                    reply
                    if reply
                    else "[no response]",
                    flush=True,
                )

                print(
                    "[brain "
                    f"{result['elapsed']:.3f}s"
                    " | finish "
                    f"{result['finish_reason']}"
                    "]",
                    flush=True,
                )

                # YUKI speaks directly as soon as the brain finishes.
                # Do not wait for Twitch EventSub to return the message.
                if reply and self.tts_worker is not None:
                    self.tts_worker.submit(
                        reply,
                        priority=TTSWorker.YUKI_PRIORITY,
                    )

                if reply and self.send_reply is not None:
                    priority_echo_marked = False

                    # Mark the outgoing Twitch echo so EventSub does not
                    # make us speak the exact same YUKI reply twice.
                    if self.tts_worker is not None:
                        self.tts_worker.mark_priority_echo(reply)
                        priority_echo_marked = True

                    try:
                        self.send_reply(reply)

                        print(
                            "[twitch reply sent]",
                            flush=True,
                        )

                    except Exception as exc:
                        if (
                            priority_echo_marked
                            and self.tts_worker is not None
                        ):
                            self.tts_worker.cancel_priority_echo(reply)

                        print(
                            f"[twitch send error: {exc}]",
                            flush=True,
                        )

                # A routed @yuki/!yuki message is still read aloud,
                # but only AFTER YUKI's priority response has been queued.
                if (
                    spoken_message
                    and self.tts_worker is not None
                ):
                    self.tts_worker.submit(
                        spoken_message,
                        priority=TTSWorker.NORMAL_PRIORITY,
                    )

                if (
                    result["used_fallback"]
                    or result["hard_failures"]
                ):
                    print(
                        "[guard: "
                        + ",".join(
                            result[
                                "hard_failures"
                            ]
                        )
                        + "]",
                        flush=True,
                    )

                print()

            except Exception as exc:
                print(
                    f"[YUKI brain error: {exc}]",
                    flush=True,
                )

            finally:
                self.queue.task_done()


def configure_console():
    try:
        sys.stdout.reconfigure(
            encoding="utf-8",
            errors="replace",
        )
    except Exception:
        pass


def load_json(path):
    return json.loads(
        path.read_text(encoding="utf-8-sig")
    )


def save_json(path, data):
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    path.write_text(
        json.dumps(
            data,
            indent=2,
            ensure_ascii=False,
        ) + "\n",
        encoding="utf-8",
    )


def request_json(
    url,
    method="GET",
    headers=None,
    form=None,
    body=None,
):
    headers = dict(headers or {})

    data = None

    if form is not None:
        data = urlencode(form).encode("utf-8")
        headers.setdefault(
            "Content-Type",
            "application/x-www-form-urlencoded",
        )

    elif body is not None:
        data = json.dumps(body).encode("utf-8")
        headers.setdefault(
            "Content-Type",
            "application/json",
        )

    req = Request(
        url,
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urlopen(req, timeout=20) as response:
            raw = response.read()

            if not raw:
                return {}

            return json.loads(
                raw.decode("utf-8")
            )

    except HTTPError as exc:
        raw = exc.read().decode(
            "utf-8",
            errors="replace",
        )

        try:
            payload = json.loads(raw)
        except Exception:
            payload = {
                "status": exc.code,
                "message": raw,
            }

        raise RuntimeError(
            json.dumps(
                payload,
                ensure_ascii=False,
            )
        ) from exc


def validate_token(token):
    req = Request(
        VALIDATE_URL,
        headers={
            "Authorization": f"OAuth {token}",
        },
    )

    try:
        with urlopen(req, timeout=15) as response:
            return json.loads(
                response.read().decode("utf-8")
            )
    except Exception:
        return None


def refresh_token(client_id, stored):
    refresh = stored.get("refresh_token")

    if not refresh:
        return None

    try:
        result = request_json(
            TOKEN_URL,
            method="POST",
            form={
                "client_id": client_id,
                "grant_type": "refresh_token",
                "refresh_token": refresh,
            },
        )

    except Exception:
        return None

    if "access_token" not in result:
        return None

    save_json(
        TOKEN_PATH,
        result,
    )

    return result


def device_authorize(client_id):
    device = request_json(
        DEVICE_URL,
        method="POST",
        form={
            "client_id": client_id,
            "scopes": SCOPES,
        },
    )

    verification_uri = device["verification_uri"]
    user_code = device["user_code"]

    print()
    print("TWITCH AUTHORIZATION")
    print("--------------------")
    print(f"Code: {user_code}")
    print()
    print("Opening Twitch authorization page...")
    print(verification_uri)
    print()

    webbrowser.open(
        verification_uri
    )

    interval = max(
        int(device.get("interval", 5)),
        1,
    )

    deadline = (
        time.monotonic()
        + int(device.get("expires_in", 1800))
    )

    while time.monotonic() < deadline:
        time.sleep(interval)

        try:
            token = request_json(
                TOKEN_URL,
                method="POST",
                form={
                    "client_id": client_id,
                    "scopes": SCOPES,
                    "device_code": device["device_code"],
                    "grant_type":
                        "urn:ietf:params:oauth:grant-type:device_code",
                },
            )

        except RuntimeError as exc:
            text = str(exc)

            if "authorization_pending" in text:
                continue

            raise

        if "access_token" in token:
            save_json(
                TOKEN_PATH,
                token,
            )

            return token

    raise RuntimeError(
        "Twitch device authorization expired."
    )


def get_token(client_id):
    stored = None

    if TOKEN_PATH.exists():
        try:
            stored = load_json(
                TOKEN_PATH
            )
        except Exception:
            stored = None

    if stored:
        access = stored.get(
            "access_token"
        )

        if access:
            validation = validate_token(
                access
            )

            if validation:
                scopes = set(
                    validation.get(
                        "scopes",
                        [],
                    )
                )

                if "user:read:chat" in scopes:
                    return (
                        stored,
                        validation,
                    )

        refreshed = refresh_token(
            client_id,
            stored,
        )

        if refreshed:
            validation = validate_token(
                refreshed["access_token"]
            )

            if validation:
                return (
                    refreshed,
                    validation,
                )

    token = device_authorize(
        client_id
    )

    validation = validate_token(
        token["access_token"]
    )

    if not validation:
        raise RuntimeError(
            "Twitch returned a token that could not be validated."
        )

    return token, validation


def helix_headers(client_id, token):
    return {
        "Client-Id": client_id,
        "Authorization":
            f"Bearer {token}",
    }


def send_chat_message(
    client_id,
    token,
    broadcaster_id,
    sender_id,
    message,
):
    message = str(message or "").strip()

    if not message:
        return None

    message = message[:500]

    result = request_json(
        HELIX_CHAT_MESSAGES,
        method="POST",
        headers=helix_headers(
            client_id,
            token,
        ),
        body={
            "broadcaster_id": broadcaster_id,
            "sender_id": sender_id,
            "message": message,
        },
    )

    data = result.get("data", [])

    if not data:
        raise RuntimeError(
            "Twitch returned no send result."
        )

    sent = data[0]

    if not sent.get("is_sent"):
        reason = sent.get("drop_reason") or {}

        raise RuntimeError(
            "Twitch rejected chat message: "
            + str(reason.get("code", "unknown"))
            + " - "
            + str(reason.get("message", "unknown"))
        )

    return sent


def get_user_id(
    login,
    client_id,
    token,
):
    url = (
        HELIX_USERS
        + "?"
        + urlencode({
            "login": login,
        })
    )

    result = request_json(
        url,
        headers=helix_headers(
            client_id,
            token,
        ),
    )

    users = result.get(
        "data",
        [],
    )

    if not users:
        raise RuntimeError(
            f"Twitch channel not found: {login}"
        )

    return users[0]


def create_chat_subscription(
    client_id,
    token,
    broadcaster_id,
    user_id,
    session_id,
):
    payload = {
        "type": "channel.chat.message",
        "version": "1",
        "condition": {
            "broadcaster_user_id":
                broadcaster_id,
            "user_id":
                user_id,
        },
        "transport": {
            "method": "websocket",
            "session_id": session_id,
        },
    }

    return request_json(
        EVENTSUB_SUBS,
        method="POST",
        headers=helix_headers(
            client_id,
            token,
        ),
        body=payload,
    )


def receive_json(ws):
    raw = ws.recv()

    if raw is None:
        raise RuntimeError(
            "Twitch WebSocket closed."
        )

    return json.loads(raw)


def print_chat_event(
    event,
    brain_worker,
    tts_worker,
):
    chatter = (
        event.get("chatter_user_name")
        or event.get("chatter_user_login")
        or "unknown"
    )

    message = (
        event.get("message", {})
        .get("text", "")
    )

    print(
        f"[{chatter}] {message}",
        flush=True,
    )

    text = message.strip()
    lowered = text.lower()

    routed = None

    if lowered.startswith("@yuki"):
        routed = text[5:].strip()

    elif lowered.startswith("!yuki"):
        routed = text[5:].strip()

    if not text:
        return

    # YUKI's outgoing Twitch message has already been submitted
    # directly to the priority TTS queue. Consume the EventSub
    # echo without speaking it again.
    if tts_worker.consume_priority_echo(text):
        return

    post_visualizer_message(
        "twitch",
        chatter,
        message,
    )

    spoken = f"{chatter} said: {message}"

    if routed:
        # Do NOT start speaking the trigger now. It would occupy
        # the only TTS worker while YUKI is thinking.
        brain_worker.submit(
            chatter,
            routed,
            spoken_message=None,
        )

    else:
        tts_worker.submit(
            spoken,
            priority=TTSWorker.NORMAL_PRIORITY,
        )


def run():
    configure_console()

    config = load_json(
        CONFIG_PATH
    )

    client_id = config[
        "client_id"
    ].strip()

    channel = config[
        "channel"
    ].strip().lower()

    print("[startup] validating Twitch token...", flush=True)

    token_data, validation = get_token(
        client_id
    )

    print("[startup] Twitch token OK", flush=True)

    access_token = token_data[
        "access_token"
    ]

    auth_user_id = validation[
        "user_id"
    ]

    auth_login = validation.get(
        "login",
        "unknown",
    )

    print("[startup] resolving Twitch channel...", flush=True)

    broadcaster = get_user_id(
        channel,
        client_id,
        access_token,
    )

    print("[startup] Twitch channel OK", flush=True)

    print()
    print("YUKI TWITCH CHAT")
    print("=================")
    print(
        f"Authorized as : {auth_login}"
    )
    print(
        f"Reading       : #{broadcaster['login']}"
    )
    print()
    print(
        "Waiting for Twitch EventSub..."
    )
    print()

    def send_reply(text):
        send_chat_message(
            client_id,
            access_token,
            broadcaster["id"],
            auth_user_id,
            text,
        )

    tts_worker = TTSWorker()
    tts_worker.start()

    brain_worker = ChatBrainWorker(
        send_reply=send_reply,
        tts_worker=tts_worker,
    )
    brain_worker.start()

    ws = websocket.create_connection(
        EVENTSUB_WS,
        timeout=90,
    )

    try:
        welcome = receive_json(
            ws
        )

        message_type = (
            welcome.get("metadata", {})
            .get("message_type")
        )

        if message_type != "session_welcome":
            raise RuntimeError(
                "Expected EventSub session_welcome."
            )

        session = (
            welcome["payload"]["session"]
        )

        session_id = session["id"]

        create_chat_subscription(
            client_id,
            access_token,
            broadcaster["id"],
            auth_user_id,
            session_id,
        )

        print(
            "Connected. Chat messages:"
        )
        print(
            "-------------------------"
        )

        while True:
            message = receive_json(
                ws
            )

            metadata = message.get(
                "metadata",
                {},
            )

            msg_type = metadata.get(
                "message_type"
            )

            if msg_type == "notification":
                subscription = (
                    message.get(
                        "payload",
                        {},
                    )
                    .get(
                        "subscription",
                        {},
                    )
                )

                if (
                    subscription.get(
                        "type"
                    )
                    == "channel.chat.message"
                ):
                    event = (
                        message["payload"][
                            "event"
                        ]
                    )

                    print_chat_event(event, brain_worker, tts_worker)

            elif msg_type == "session_keepalive":
                continue

            elif msg_type == "session_reconnect":
                reconnect_url = (
                    message["payload"][
                        "session"
                    ].get(
                        "reconnect_url"
                    )
                )

                print()
                print(
                    "Twitch requested reconnect."
                )

                if reconnect_url:
                    ws.close()

                    ws = (
                        websocket.create_connection(
                            reconnect_url,
                            timeout=90,
                        )
                    )

                    reconnect_welcome = (
                        receive_json(ws)
                    )

                    if (
                        reconnect_welcome
                        .get(
                            "metadata",
                            {},
                        )
                        .get(
                            "message_type"
                        )
                        != "session_welcome"
                    ):
                        raise RuntimeError(
                            "Reconnect failed."
                        )

                    print(
                        "Reconnected."
                    )

    finally:
        try:
            ws.close()
        except Exception:
            pass


if __name__ == "__main__":
    try:
        run()

    except KeyboardInterrupt:
        print()
        print("Stopped.")

    except Exception as exc:
        print()
        print(
            "TWITCH ERROR:",
            exc,
        )
        raise SystemExit(1)





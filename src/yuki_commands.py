import argparse
import json
import os
import re
import urllib.request
from pathlib import Path


DEFAULT_CONFIG_PATH = Path(
    r"C:\Yuki\config\commands.json"
)


def normalize_command_text(text):
    text = str(text or "").strip()

    text = text.replace(
        "\u3000",
        " ",
    )

    text = re.sub(
        r"\s+",
        "",
        text,
    )

    text = text.rstrip(
        "。！？!?、,"
    )

    return text.casefold()


def load_config(path=DEFAULT_CONFIG_PATH):
    with Path(path).open(
        "r",
        encoding="utf-8-sig",
    ) as handle:
        return json.load(handle)


def match_command(text, config):
    normalized = normalize_command_text(
        text
    )

    if not normalized:
        return None

    for command in config.get(
        "commands",
        [],
    ):
        for phrase in command.get(
            "phrases",
            [],
        ):
            if (
                normalize_command_text(
                    phrase
                )
                == normalized
            ):
                return dict(command)

    return None


def enumerate_entries(path):
    root = Path(path)

    if not root.exists():
        raise FileNotFoundError(
            f"Command path does not exist: {root}"
        )

    if not root.is_dir():
        raise NotADirectoryError(
            f"Command path is not a directory: {root}"
        )

    entries = []

    children = sorted(
        root.iterdir(),
        key=lambda item: (
            not item.is_dir(),
            item.name.casefold(),
        ),
    )

    for item in children[:100]:
        entries.append(
            {
                "name": item.name,
                "kind": (
                    "folder"
                    if item.is_dir()
                    else "file"
                ),
                "path": str(item),
            }
        )

    return entries


def post_explorer(url, payload):
    body = json.dumps(
        payload,
        ensure_ascii=False,
    ).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type":
                "application/json; charset=utf-8",
        },
        method="POST",
    )

    with urllib.request.urlopen(
        request,
        timeout=0.5,
    ) as response:
        return json.loads(
            response.read().decode(
                "utf-8"
            )
        )


def execute_command(command, config):
    action = str(
        command.get(
            "action",
            "",
        )
    )

    visualizer_url = str(
        config.get(
            "visualizer_url",
            "http://127.0.0.1:8085/api/explorer",
        )
    )

    if action == "explorer.hide":
        return post_explorer(
            visualizer_url,
            {
                "action": "hide",
            },
        )

    if action == "explorer.show":
        path = command.get(
            "path",
            "",
        )

        items = enumerate_entries(
            path
        )

        return post_explorer(
            visualizer_url,
            {
                "action": "show",
                "view": command.get(
                    "view",
                    "projects",
                ),
                "title": command.get(
                    "title",
                    "Projects",
                ),
                "caption": command.get(
                    "caption",
                    "Provided by YUKI",
                ),
                "items": items,
            },
        )

    raise ValueError(
        f"Unknown command action: {action}"
    )


def handle_text(
    text,
    config_path=DEFAULT_CONFIG_PATH,
):
    config = load_config(
        config_path
    )

    command = match_command(
        text,
        config,
    )

    if command is None:
        return {
            "matched": False,
            "command_id": None,
            "result": None,
        }

    result = execute_command(
        command,
        config,
    )

    return {
        "matched": True,
        "command_id": command.get(
            "id"
        ),
        "result": result,
    }


def main():
    parser = argparse.ArgumentParser(
        description=(
            "YUKI deterministic local "
            "command router"
        )
    )

    parser.add_argument(
        "--text",
        required=True,
        help="Recognized user text",
    )

    parser.add_argument(
        "--config",
        default=str(
            DEFAULT_CONFIG_PATH
        ),
        help="Path to commands.json",
    )

    args = parser.parse_args()

    result = handle_text(
        args.text,
        Path(args.config),
    )

    print(
        json.dumps(
            result,
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
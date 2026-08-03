#!/usr/bin/env python3
"""Generate THD Bot lane-position scores from authoritative hero KV.

The generated Lua is loaded by the Bot runtime. By default this script expects
THDAmethyst_Game to be a sibling of THD2BotScript and reads the ordinary Bot
roster from scripts/vscripts/util/specialmode.lua.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROSTER_TABLE = "G_Bot_Random_Hero"
FOLDER_TABLE = "G_Bot_Hero_Folder"
POSITIONS = (
    "safe_core",
    "mid",
    "off_core",
    "soft_support",
    "hard_support",
)


class GenerationError(RuntimeError):
    pass


@dataclass(frozen=True)
class HeroRecord:
    hero: str
    custom_hero: str
    folder: str
    roles: dict[str, int]
    scores: dict[str, int]


def kv_tokens(text: str) -> list[str]:
    tokens: list[str] = []
    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        if text.startswith("//", i):
            end = text.find("\n", i + 2)
            i = len(text) if end < 0 else end + 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise GenerationError("unterminated KV block comment")
            i = end + 2
            continue
        if text[i] in "{}":
            tokens.append(text[i])
            i += 1
            continue
        if text[i] == '"':
            i += 1
            value: list[str] = []
            while i < len(text):
                if text[i] == "\\" and i + 1 < len(text):
                    value.append(text[i])
                    value.append(text[i + 1])
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                value.append(text[i])
                i += 1
            else:
                raise GenerationError("unterminated KV string")
            tokens.append("".join(value))
            continue
        end = i
        while end < len(text) and not text[end].isspace() and text[end] not in "{}":
            end += 1
        tokens.append(text[i:end])
        i = end
    return tokens


def parse_kv(text: str) -> dict[str, Any]:
    tokens = kv_tokens(text)
    index = 0

    def parse_block(expect_close: bool) -> dict[str, Any]:
        nonlocal index
        result: dict[str, Any] = {}
        while index < len(tokens):
            key = tokens[index]
            if key == "}":
                if not expect_close:
                    raise GenerationError("unexpected KV closing brace")
                index += 1
                return result
            if key == "{":
                raise GenerationError("unexpected KV opening brace")
            index += 1
            if index >= len(tokens):
                raise GenerationError(f"missing KV value for {key!r}")
            if tokens[index] == "{":
                index += 1
                value: Any = parse_block(True)
            else:
                value = tokens[index]
                index += 1
            result[key] = value
        if expect_close:
            raise GenerationError("missing KV closing brace")
        return result

    return parse_block(False)


def extract_lua_string_table(text: str, table_name: str) -> list[str]:
    match = re.search(
        rf"\b{re.escape(table_name)}\s*=\s*\{{(?P<body>.*?)\n\s*\}}",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise GenerationError(f"cannot find Lua table {table_name}")
    values: list[str] = []
    for line in match.group("body").splitlines():
        line = line.split("--", 1)[0]
        values.extend(re.findall(r'"([^"]+)"', line))
    if not values:
        raise GenerationError(f"Lua table {table_name} is empty")
    return values


def parse_roles(hero_data: dict[str, Any], source: Path) -> dict[str, int]:
    raw_roles = hero_data.get("Role")
    raw_levels = hero_data.get("Rolelevels")
    if not isinstance(raw_roles, str) or not isinstance(raw_levels, str):
        raise GenerationError(f"missing Role/Rolelevels in {source}")
    roles = [value.strip() for value in raw_roles.split(",") if value.strip()]
    level_texts = [value.strip() for value in raw_levels.split(",") if value.strip()]
    if len(roles) != len(level_texts):
        raise GenerationError(
            f"Role/Rolelevels length mismatch in {source}: {len(roles)} != {len(level_texts)}"
        )
    levels: list[int] = []
    for value in level_texts:
        try:
            level = int(value)
        except ValueError as exc:
            raise GenerationError(f"invalid role level {value!r} in {source}") from exc
        if level < 0:
            raise GenerationError(f"negative role level {value!r} in {source}")
        levels.append(level)
    return dict(zip(roles, levels, strict=True))


def calculate_scores(roles: dict[str, int]) -> dict[str, int]:
    role = lambda name: roles.get(name, 0)
    return {
        "safe_core": 4 * role("Carry") + 2 * role("Jungler") + role("Pusher") + role("Escape"),
        "mid": 3 * role("Nuker") + 2 * role("Carry") + 2 * role("Escape") + role("Pusher"),
        "off_core": 3 * role("Durable") + 3 * role("Initiator") + 2 * role("Disabler") + role("Carry"),
        "soft_support": 3 * role("Support") + 2 * role("Disabler") + 2 * role("Initiator") + role("Nuker") + role("Escape"),
        "hard_support": 4 * role("LaneSupport") + 3 * role("Support") + 2 * role("Disabler") + role("Durable"),
    }


def find_custom_hero(data: dict[str, Any], override_hero: str, source: Path) -> tuple[str, dict[str, Any]]:
    roots = data.get("DOTAHeroes")
    if not isinstance(roots, dict):
        raise GenerationError(f"missing DOTAHeroes root in {source}")
    matches: list[tuple[str, dict[str, Any]]] = []
    for custom_name, hero_data in roots.items():
        if isinstance(hero_data, dict) and hero_data.get("override_hero") == override_hero:
            matches.append((custom_name, hero_data))
    if len(matches) != 1:
        raise GenerationError(
            f"expected one override_hero={override_hero!r} in {source}, found {len(matches)}"
        )
    return matches[0]


def build_records(game_root: Path) -> tuple[list[HeroRecord], str]:
    specialmode = game_root / "scripts" / "vscripts" / "util" / "specialmode.lua"
    if not specialmode.is_file():
        raise GenerationError(f"missing specialmode.lua: {specialmode}")
    specialmode_text = specialmode.read_text(encoding="utf-8-sig")
    heroes = extract_lua_string_table(specialmode_text, ROSTER_TABLE)
    folders = extract_lua_string_table(specialmode_text, FOLDER_TABLE)
    if len(heroes) != len(folders):
        raise GenerationError(f"roster/folder length mismatch: {len(heroes)} != {len(folders)}")
    if len(set(heroes)) != len(heroes):
        raise GenerationError("duplicate hero slot in ordinary Bot roster")
    if len(set(folders)) != len(folders):
        raise GenerationError("duplicate hero folder in ordinary Bot roster")

    digest = hashlib.sha256()
    # Only hash the two roster tables, so unrelated specialmode.lua edits do not
    # make the generated Bot data appear stale.
    digest.update("\0".join(heroes).encode("utf-8"))
    digest.update("\0".join(folders).encode("utf-8"))
    records: list[HeroRecord] = []
    seen_overrides: set[str] = set()
    for hero, folder in zip(heroes, folders, strict=True):
        source = game_root / "scripts" / "npc" / "heroes" / folder / "hero.txt"
        if not source.is_file():
            raise GenerationError(f"missing hero.txt for {hero}: {source}")
        source_text = source.read_text(encoding="utf-8-sig")
        digest.update(folder.encode("utf-8"))
        digest.update(source_text.encode("utf-8"))
        custom_hero, hero_data = find_custom_hero(parse_kv(source_text), hero, source)
        if hero in seen_overrides:
            raise GenerationError(f"duplicate override_hero mapping: {hero}")
        seen_overrides.add(hero)
        roles = parse_roles(hero_data, source)
        records.append(HeroRecord(hero, custom_hero, folder, roles, calculate_scores(roles)))
    return records, digest.hexdigest()


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_lua(records: list[HeroRecord], source_digest: str) -> str:
    lines = [
        "-- Generated by tools/generate_lane_assignment.py. Do not edit by hand.",
        "-- Source: THDAmethyst_Game hero.txt Role/Rolelevels and ordinary Bot roster.",
        "return {",
        "\tmetadata = {",
        f"\t\theroCount = {len(records)},",
        f"\t\tsourceDigest = {lua_quote(source_digest)},",
        "\t},",
        "\theroes = {",
    ]
    for record in records:
        lines.extend(
            [
                f"\t\t[{lua_quote(record.hero)}] = {{",
                f"\t\t\tcustomHero = {lua_quote(record.custom_hero)},",
                f"\t\t\tfolder = {lua_quote(record.folder)},",
                "\t\t\troles = {",
            ]
        )
        for name in sorted(record.roles):
            lines.append(f"\t\t\t\t[{lua_quote(name)}] = {record.roles[name]},")
        lines.extend(["\t\t\t},", "\t\t\tscores = {"])
        for position in POSITIONS:
            lines.append(f"\t\t\t\t{position} = {record.scores[position]},")
        lines.extend(["\t\t\t},", "\t\t},"])
    lines.extend(["\t},", "}", ""])
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    bot_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, default=bot_root.parent / "THDAmethyst_Game")
    parser.add_argument(
        "--output",
        type=Path,
        default=bot_root / "THDFuncLib" / "lane_assignment_generated.lua",
    )
    parser.add_argument("--check", action="store_true", help="fail if the generated output is stale")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        records, source_digest = build_records(args.game_root.resolve())
        rendered = render_lua(records, source_digest)
        output = args.output.resolve()
        if args.check:
            if not output.is_file() or output.read_text(encoding="utf-8") != rendered:
                raise GenerationError(f"generated lane data is stale: {output}")
            print(f"lane assignment data is current: heroes={len(records)} digest={source_digest[:16]}")
            return 0
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8", newline="\n")
        print(f"generated {output}: heroes={len(records)} digest={source_digest[:16]}")
        return 0
    except (GenerationError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

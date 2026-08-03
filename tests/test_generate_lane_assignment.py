from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


BOT_ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = BOT_ROOT / "tools" / "generate_lane_assignment.py"
SPEC = importlib.util.spec_from_file_location("generate_lane_assignment", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
generator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generator
SPEC.loader.exec_module(generator)


def hero_text(custom: str, override: str, roles: str, levels: str, extra: str = "") -> str:
    return f'''"DOTAHeroes"
{{
    "{custom}"
    {{
        "override_hero" "{override}"
        // "Role" "Carry,Support"
        // "Rolelevels" "3,3"
        "Role" "{roles}"
        "Rolelevels" "{levels}"
        {extra}
    }}
}}
'''


class GenerateLaneAssignmentTests(unittest.TestCase):
    def make_game(self, root: Path, heroes: list[str], folders: list[str]) -> Path:
        specialmode = root / "scripts" / "vscripts" / "util" / "specialmode.lua"
        specialmode.parent.mkdir(parents=True)
        quoted_heroes = "\n".join(f'    "{value}",' for value in heroes)
        quoted_folders = "\n".join(f'    "{value}",' for value in folders)
        specialmode.write_text(
            f"G_Bot_Random_Hero = {{\n{quoted_heroes}\n}}\n"
            f"G_Bot_Hero_Folder = {{\n{quoted_folders}\n}}\n",
            encoding="utf-8",
        )
        return root

    def add_hero(self, root: Path, folder: str, content: str) -> None:
        path = root / "scripts" / "npc" / "heroes" / folder / "hero.txt"
        path.parent.mkdir(parents=True)
        path.write_text(content, encoding="utf-8")

    def test_fixed_score_formula(self) -> None:
        scores = generator.calculate_scores(
            {
                "Carry": 3,
                "Support": 2,
                "Nuker": 1,
                "Disabler": 2,
                "Jungler": 3,
                "Durable": 1,
                "Escape": 2,
                "LaneSupport": 3,
                "Pusher": 1,
                "Initiator": 2,
            }
        )
        self.assertEqual(
            scores,
            {"safe_core": 21, "mid": 14, "off_core": 16, "soft_support": 17, "hard_support": 23},
        )

    def test_comments_are_ignored_and_records_map_by_override(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_game(Path(temporary), ["npc_dota_hero_lina"], ["reimu"])
            self.add_hero(root, "reimu", hero_text("npc_dota_hero_reimu", "npc_dota_hero_lina", "Support,Nuker", "3,1"))
            records, digest = generator.build_records(root)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].custom_hero, "npc_dota_hero_reimu")
        self.assertEqual(records[0].roles, {"Support": 3, "Nuker": 1})
        self.assertEqual(len(digest), 64)

    def test_role_level_mismatch_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_game(Path(temporary), ["npc_dota_hero_lina"], ["reimu"])
            self.add_hero(root, "reimu", hero_text("reimu", "npc_dota_hero_lina", "Carry,Support", "3"))
            with self.assertRaisesRegex(generator.GenerationError, "length mismatch"):
                generator.build_records(root)

    def test_missing_hero_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_game(Path(temporary), ["npc_dota_hero_lina"], ["reimu"])
            with self.assertRaisesRegex(generator.GenerationError, "missing hero.txt"):
                generator.build_records(root)

    def test_duplicate_override_inside_folder_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_game(Path(temporary), ["npc_dota_hero_lina"], ["reimu"])
            content = '''"DOTAHeroes"
{
    "one" { "override_hero" "npc_dota_hero_lina" "Role" "Carry" "Rolelevels" "3" }
    "two" { "override_hero" "npc_dota_hero_lina" "Role" "Support" "Rolelevels" "3" }
}
'''
            self.add_hero(root, "reimu", content)
            with self.assertRaisesRegex(generator.GenerationError, "expected one override_hero"):
                generator.build_records(root)

    def test_current_roster_and_generated_output_are_complete(self) -> None:
        records, digest = generator.build_records(BOT_ROOT.parent / "THDAmethyst_Game")
        rendered = generator.render_lua(records, digest)
        generated = (BOT_ROOT / "THDFuncLib" / "lane_assignment_generated.lua").read_text(encoding="utf-8")
        self.assertEqual(len(records), 69)
        self.assertEqual(rendered, generated)


if __name__ == "__main__":
    unittest.main()

import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts/services/configure-radarr-quality-policy.py"
spec = importlib.util.spec_from_file_location("radarr_quality_policy", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_high_quality_1080p_policy_disables_remux_and_4k_and_caps_other_qualities():
    definitions = [
        {"quality": {"name": "WEB 1080p"}, "maxSize": 0},
        {"quality": {"name": "Bluray-2160p Remux"}, "maxSize": 0},
    ]
    profiles = [{"name": "Any", "items": [
        {"allowed": True, "quality": {"name": "WEB 1080p"}},
        {"allowed": True, "quality": {"name": "Bluray-2160p Remux"}},
    ]}]

    changed_definitions, changed_profiles = module.apply_high_quality_1080p_policy(definitions, profiles, 100)

    assert changed_definitions[0]["maxSize"] == 100
    assert changed_definitions[1]["maxSize"] == 0
    assert changed_profiles[0]["items"][0]["allowed"] is True
    assert changed_profiles[0]["items"][1]["allowed"] is False


test_high_quality_1080p_policy_disables_remux_and_4k_and_caps_other_qualities()

"""Tests for router.environments -- environment registry and lookup."""

import pytest

from router.environments import (
    DEFAULT_ENVIRONMENT_ID,
    ENVIRONMENT_MAP,
    ENVIRONMENTS,
    resolve_image,
)


class TestEnvironmentRegistry:
    def test_default_environment_exists(self):
        assert DEFAULT_ENVIRONMENT_ID in ENVIRONMENT_MAP

    def test_all_environments_have_unique_ids(self):
        ids = [env.id for env in ENVIRONMENTS]
        assert len(ids) == len(set(ids))

    def test_all_environments_have_images(self):
        for env in ENVIRONMENTS:
            assert env.image, f"Environment '{env.id}' has no image"

    def test_expected_environments_present(self):
        ids = {env.id for env in ENVIRONMENTS}
        assert "default" in ids
        assert "python-analysis" in ids
        assert "infra" in ids


class TestResolveImage:
    def test_resolve_known_id(self):
        image = resolve_image("default")
        assert image == ENVIRONMENT_MAP["default"].image

    def test_resolve_python_analysis(self):
        image = resolve_image("python-analysis")
        assert "python-agent" in image

    def test_resolve_infra(self):
        image = resolve_image("infra")
        assert "infra-agent" in image

    def test_resolve_unknown_id_returns_default(self):
        image = resolve_image("nonexistent")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image

    def test_resolve_none_returns_default(self):
        image = resolve_image(None)
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image

    def test_resolve_empty_string_returns_default(self):
        image = resolve_image("")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image

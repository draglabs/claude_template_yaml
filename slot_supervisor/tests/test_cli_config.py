import io
import json
import os

from helpers import SupervisorCase, write_template
from slots.cli import main
from slots.config import Settings, Tokens, serve_settings
from slots.errors import ConfigError
from slots.templates import load_template

ENV = {
    "SLOTS_HOST": "slots.test", "SLOTS_UPSTREAM_HOST": "upstream.test",
    "SLOTS_TEMPLATES_DIR": "/t", "SLOTS_WORK_DIR": "/w", "SLOTS_ROUTES_DIR": "/r",
    "SLOTS_PORT_RANGE": "20000-20999", "SLOTS_MAX_RUNNING": "8",
    "SLOTS_PROXY_RELOAD_COMMAND": "caddy reload --config /etc/caddy/Caddyfile",
}


class CliTests(SupervisorCase):
    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        code = main(list(argv), supervisor=self.supervisor, environ={}, out=out, err=err)
        return code, out.getvalue(), err.getvalue()

    def test_the_verbs(self):
        code, out, _ = self.run_cli("request", "--project", "alpha", "--ticket", "T-1", "--agent", "dev-agent")
        self.assertEqual((code, json.loads(out)["slot"]), (0, "alpha-1"))
        code, out, _ = self.run_cli("check", "alpha-1")
        self.assertEqual((code, json.loads(out)["state"]), (0, "running"))
        code, out, _ = self.run_cli("reset", "alpha-1")
        self.assertEqual((code, json.loads(out)["ticket"]), (0, "T-1"))
        code, out, _ = self.run_cli("list")
        self.assertEqual([s["slot"] for s in json.loads(out)["slots"]], ["alpha-1"])
        self.clock.forward(hours=8)
        code, out, _ = self.run_cli("reap")
        self.assertEqual((code, json.loads(out)), (0, {"stopped": ["alpha-1"], "failed": []}))
        self.run_cli("request", "--project", "beta", "--ticket", "T-2", "--agent", "dev-agent")
        self.assertEqual(self.run_cli("release", "beta-1"), (0, "", ""))
        self.assertEqual(self.runtime.projects, {})

    def test_a_refusal_exits_1_with_a_code(self):
        code, out, err = self.run_cli("request", "--project", "gamma", "--ticket", "T-1", "--agent", "a")
        self.assertEqual((code, out), (1, ""))
        self.assertEqual(json.loads(err)["error"]["code"], "not_found")

    def test_missing_settings_fail_loudly(self):
        err = io.StringIO()
        code = main(["list"], environ={}, out=io.StringIO(), err=err)
        self.assertEqual(code, 1)
        self.assertIn("missing required setting SLOTS_HOST", err.getvalue())


class ConfigTests(SupervisorCase):
    def test_settings_from_env(self):
        settings = Settings.from_env(ENV)
        self.assertEqual((settings.port_low, settings.port_high, settings.max_running), (20000, 20999, 8))
        self.assertEqual(settings.ssh_host, "slots.test")
        self.assertEqual(settings.ttl.total_seconds(), 8 * 3600)
        self.assertEqual(settings.proxy_reload_command, ["caddy", "reload", "--config", "/etc/caddy/Caddyfile"])
        self.assertEqual(Settings.from_env(dict(ENV, SLOTS_SSH_HOST="ssh.test")).ssh_host, "ssh.test")

    def test_every_required_setting_is_required(self):
        for key in ENV:
            env = dict(ENV)
            del env[key]
            with self.assertRaises(ConfigError, msg=key) as caught:
                Settings.from_env(env)
            self.assertIn(key, str(caught.exception))
        with self.assertRaises(ConfigError):
            Settings.from_env(dict(ENV, SLOTS_PORT_RANGE="20000"))
        with self.assertRaises(ConfigError):
            Settings.from_env(dict(ENV, SLOTS_MAX_RUNNING="many"))

    def test_serve_settings(self):
        env = {"SLOTS_LISTEN": "localhost:8700", "SLOTS_TOKENS_FILE": "/etc/slot-supervisor/tokens.json"}
        self.assertEqual(serve_settings(env), ("localhost", 8700, "/etc/slot-supervisor/tokens.json"))
        with self.assertRaises(ConfigError):
            serve_settings({"SLOTS_LISTEN": "localhost:8700"})
        with self.assertRaises(ConfigError):
            serve_settings(dict(env, SLOTS_LISTEN="8700"))

    def test_tokens_file(self):
        path = os.path.join(self.tmp, "tokens.json")
        with open(path, "w") as handle:
            json.dump({"admin": "admin-token-0123456789", "projects": {"alpha": "alpha-token-0123456789"}}, handle)
        os.chmod(path, 0o644)
        with self.assertRaises(ConfigError):
            Tokens.load(path)  # readable by others
        os.chmod(path, 0o600)
        tokens = Tokens.load(path)
        self.assertEqual(tokens.scope_for("admin-token-0123456789"), "*")
        self.assertEqual(tokens.scope_for("alpha-token-0123456789"), "alpha")
        self.assertIsNone(tokens.scope_for("something-else-entirely"))
        with self.assertRaises(ConfigError):
            Tokens("same-token-0123456789", {"alpha": "same-token-0123456789"})
        with self.assertRaises(ConfigError):
            Tokens.load(os.path.join(self.tmp, "missing.json"))

    def test_a_broken_template_fails_loudly(self):
        self.assertEqual(load_template(self.templates, "alpha").cap, 2)
        for changes in ({"cap": 0}, {"ports": ["db"]}, {"seed_command": "sh seed.sh"},
                        {"health_path": "healthz"}, {"database": "postgres://{host}:{port_cache}/x"},
                        {"surprise": 1}):
            write_template(self.templates, "broken", **changes)
            with self.assertRaises(ConfigError, msg=changes):
                load_template(self.templates, "broken")

    def test_strip_prefix_is_now_an_unknown_key(self):
        write_template(self.templates, "old", strip_prefix=True)
        with self.assertRaises(ConfigError) as caught:
            load_template(self.templates, "old")
        self.assertIn("unknown keys ['strip_prefix']", str(caught.exception))

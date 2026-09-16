#!/usr/bin/python3
"""Tests for scripts/dim-usage.

The collector is the only place that knows the shape of `dim usage --json` and
of Dim's own usage database, so it is tested against both: a stub `dim` for the
subscription half and a synthetic dimcode.sqlite for the local ledger. Nothing
here touches the real account, and the one test that reads a real database only
does so read-only and skips when there is none.

Run: python3 tests/test_dim_usage.py
"""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
COLLECTOR = PLUGIN_ROOT / "scripts" / "dim-usage"

# Trimmed from a real `dim usage --json`: the nesting is what the collector has
# to get right (credits and feature_meters sit at the top level, not inside
# `subscription`).
SUBSCRIPTION_PAYLOAD = {
  "account_id": 2039,
  "subscription": {
    "subscription": {
      "id": 3099,
      "kind": "plan",
      "status": "active",
      "line": "dimcode",
      "cancel_at_period_end": False,
    },
    "current_term": {
      "id": 3890,
      "start_at": "2026-09-13T12:33:46.906Z",
      "end_at": "2026-10-13T12:33:46.906Z",
      "status": "active",
      "entitlement_payload_json": json.dumps({
        "compact_model": "deepseek-v4-flash",
        "quota_policy": {"grant_units": 48000000},
        "remote_control_enabled": True,
        "model_access": [
          {"model": "deepseek-v4-flash", "config": {"displayName": "DeepSeek-V4-Flash"}},
          {"model": "glm-5.3"},
          {"model": "seed-2.1-pro", "config": {"displayName": "Seed 2.1 Pro"}},
        ],
      }),
    },
    "product": {
      "name": "Pro",
      "description": "roughly 6000 conversations",
      "product_type": "subscription",
    },
    "price": {
      "amount": 29900,
      "currency": "CNY",
      "billing_interval": "month",
      "provider": "alipay",
    },
  },
  "credits": {
    "subscription_bucket": {
      "id": 6290,
      "total_units": 48000,
      "used_units": 5198,
      "remaining_units": 42802,
      "expires_at": "2026-10-13T12:33:46.906Z",
      "status": "active",
    },
    "addon_buckets": [],
    "total_units": 48000,
    "used_units": 5198,
    "remaining_units": 42802,
  },
  "resets": {"window": {"available_count": 1}, "monthly_full": {"available_count": 0}},
  "feature_meters": [
    {
      "feature_key": "web_search",
      "total_remaining": 2400,
      "unit": "call",
      "unlimited": False,
      "total_allowance": 2400,
      "total_used": 0,
      "period_end": "2026-10-13T12:33:46.906Z",
    }
  ],
  "config": {"compact_model": "deepseek-v4.1-flash", "remote_control_enabled": True},
}

USAGE_SCHEMA = """
create table usage_daily_stats (
  day text primary key,
  inputTokens integer not null,
  outputTokens integer not null,
  totalTokens integer not null,
  cacheReadTokens integer not null default 0,
  cacheWriteTokens integer not null default 0,
  estimatedCostUsd real not null,
  runCount integer not null,
  sessionCount integer not null,
  skillUseCount integer not null,
  active integer not null,
  updatedAt text not null
);
create table usage_run_stats (
  runId text primary key,
  sessionId text not null,
  providerId text not null,
  modelId text not null,
  status text not null,
  startedAt text,
  endedAt text not null,
  durationMs integer,
  inputTokens integer not null,
  outputTokens integer not null,
  totalTokens integer not null,
  cacheReadTokens integer,
  cacheWriteTokens integer,
  cost text not null,
  pricing text not null,
  createdAt text not null,
  updatedAt text not null
);
"""


def write_stub(path: Path, body: str) -> Path:
  path.write_text("#!/bin/bash\n" + body)
  path.chmod(0o755)
  return path


def iso(offset_days: float = 0) -> str:
  return (datetime.now(timezone.utc) + timedelta(days=offset_days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def day_key(offset_days: int = 0) -> str:
  return (datetime.now().astimezone() + timedelta(days=offset_days)).strftime("%Y-%m-%d")


def build_usage_db(path: Path, days: list[dict], runs: list[dict]) -> Path:
  """A dimcode.sqlite with just the two tables the collector reads."""
  if path.exists():
    path.unlink()
  conn = sqlite3.connect(path)
  conn.executescript(USAGE_SCHEMA)
  for day in days:
    conn.execute(
      "insert into usage_daily_stats (day, inputTokens, outputTokens, totalTokens, cacheReadTokens,"
      " cacheWriteTokens, estimatedCostUsd, runCount, sessionCount, skillUseCount, active, updatedAt)"
      " values (?,?,?,?,?,?,?,?,?,?,?,?)",
      (day["day"], day.get("inputTokens", day["totalTokens"]), day.get("outputTokens", 0),
       day["totalTokens"], day.get("cacheReadTokens", 0), day.get("cacheWriteTokens", 0),
       day.get("estimatedCostUsd", 0.0), day.get("runCount", 1), day.get("sessionCount", 1),
       day.get("skillUseCount", 0), 1, iso()),
    )
  for index, run in enumerate(runs):
    conn.execute(
      "insert into usage_run_stats (runId, sessionId, providerId, modelId, status, endedAt,"
      " inputTokens, outputTokens, totalTokens, cacheReadTokens, cacheWriteTokens, cost, pricing,"
      " createdAt, updatedAt) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      (f"run_{index}", run.get("sessionId", "sess_1"), run.get("providerId", "dimcode-api-oauth"),
       run["modelId"], "completed", run.get("endedAt", iso()), run.get("inputTokens", 0),
       run.get("outputTokens", 0), run.get("totalTokens", 0), run.get("cacheReadTokens", 0),
       run.get("cacheWriteTokens", 0), run.get("cost", "{}"), "{}", iso(), iso()),
    )
  conn.commit()
  conn.close()
  return path


class CollectorTestCase(unittest.TestCase):
  """Runs the collector as the widget does: a process, JSON on stdout."""

  def setUp(self) -> None:
    self.temp = tempfile.TemporaryDirectory(prefix="guo-dim-test-")
    self.root = Path(self.temp.name)
    self.codex_home = self.root / "codex"
    self.usage_db = self.root / "dimcode.sqlite"
    self.settings = write_stub(self.root / "dim-ok", f"cat <<'JSON'\n{json.dumps(SUBSCRIPTION_PAYLOAD)}\nJSON\n")

  def tearDown(self) -> None:
    self.temp.cleanup()

  def run_collector(self, *args: str, dim_bin: Path | None = None,
                    usage_db: Path | None = None) -> tuple[dict, int]:
    env = dict(os.environ)
    env["DIM_BIN"] = str(dim_bin if dim_bin is not None else self.settings)
    db = usage_db if usage_db is not None else self.usage_db
    command = [sys.executable, str(COLLECTOR), *args]
    if db is not None:
      command += ["--usage-db", str(db)]
    proc = subprocess.run(command, capture_output=True, text=True, env=env, timeout=60)
    payload = json.loads(proc.stdout or "{}")
    return payload, proc.returncode

  # ------------------------------------------------------------ subscription

  def test_subscription_normalized_from_top_level_credits(self) -> None:
    snapshot, code = self.run_collector("--no-tokens")
    self.assertEqual(code, 0)
    self.assertTrue(snapshot["ok"])
    self.assertEqual(snapshot["dimPath"], str(self.settings))
    self.assertEqual(snapshot["accountId"], 2039)
    self.assertEqual(snapshot["plan"]["name"], "Pro")
    self.assertEqual(snapshot["plan"]["priceAmount"], 29900)
    self.assertEqual(snapshot["plan"]["interval"], "month")
    self.assertEqual(snapshot["credits"]["total"], 48000)
    self.assertEqual(snapshot["credits"]["used"], 5198)
    self.assertEqual(snapshot["credits"]["remaining"], 42802)
    self.assertAlmostEqual(snapshot["credits"]["usedFraction"], 0.10829, places=4)
    # The compact model comes from the live config, not the term template.
    self.assertEqual(snapshot["compactModel"], "deepseek-v4.1-flash")
    self.assertEqual(snapshot["term"]["endAt"], "2026-10-13T12:33:46.906Z")
    self.assertEqual(snapshot["term"]["windowResetsAvailable"], 1)
    self.assertEqual(snapshot["models"]["count"], 3)
    self.assertIn("DeepSeek-V4-Flash", snapshot["models"]["names"])

  def test_feature_meters_carry_label_and_remaining(self) -> None:
    snapshot, _ = self.run_collector("--no-tokens")
    self.assertEqual(len(snapshot["features"]), 1)
    meter = snapshot["features"][0]
    self.assertEqual(meter["key"], "web_search")
    self.assertEqual(meter["label"], "Web search")
    self.assertEqual(meter["allowance"], 2400)
    self.assertEqual(meter["remaining"], 2400)
    self.assertEqual(meter["unit"], "call")

  def test_cancelling_subscription_is_reported(self) -> None:
    payload = json.loads(json.dumps(SUBSCRIPTION_PAYLOAD))
    payload["subscription"]["subscription"]["cancel_at_period_end"] = True
    stub = write_stub(self.root / "dim-cancelling", f"cat <<'JSON'\n{json.dumps(payload)}\nJSON\n")
    snapshot, _ = self.run_collector("--no-tokens", dim_bin=stub)
    self.assertTrue(snapshot["subscription"]["cancelAtPeriodEnd"])

  def test_missing_cli_reports_why(self) -> None:
    snapshot, code = self.run_collector("--no-tokens", dim_bin=self.root / "absent")
    self.assertEqual(code, 1)
    self.assertFalse(snapshot["ok"])
    self.assertFalse(snapshot["dimFound"])
    self.assertIn("not an executable file", snapshot["error"])

  def test_failing_cli_surfaces_stderr(self) -> None:
    stub = write_stub(self.root / "dim-fail", "echo 'not signed in' >&2\nexit 1\n")
    snapshot, code = self.run_collector("--no-tokens", dim_bin=stub)
    self.assertEqual(code, 1)
    self.assertFalse(snapshot["ok"])
    self.assertIn("not signed in", snapshot["error"])

  def test_non_json_output_is_reported_not_raised(self) -> None:
    stub = write_stub(self.root / "dim-noise", "echo 'looking for updates...'\n")
    snapshot, code = self.run_collector("--no-tokens", dim_bin=stub)
    self.assertEqual(code, 1)
    self.assertFalse(snapshot["ok"])
    self.assertIn("did not return JSON", snapshot["error"])

  def test_zero_grant_falls_back_to_entitlement(self) -> None:
    payload = json.loads(json.dumps(SUBSCRIPTION_PAYLOAD))
    del payload["credits"]
    stub = write_stub(self.root / "dim-no-credits", f"cat <<'JSON'\n{json.dumps(payload)}\nJSON\n")
    snapshot, _ = self.run_collector("--no-tokens", dim_bin=stub)
    self.assertEqual(snapshot["credits"]["total"], 48000000)
    self.assertEqual(snapshot["credits"]["remaining"], 48000000)

  def test_hanging_cli_times_out_and_still_reports(self) -> None:
    stub = write_stub(self.root / "dim-hang", "sleep 30\n")
    snapshot, code = self.run_collector("--no-tokens", "--timeout", "1", dim_bin=stub)
    self.assertEqual(code, 1)
    self.assertFalse(snapshot["ok"])
    self.assertIn("timed out after 1s", snapshot["error"])
    self.assertEqual(snapshot["dimPath"], str(stub))

  def test_timeout_env_variable_is_honoured(self) -> None:
    stub = write_stub(self.root / "dim-hang-env", "sleep 30\n")
    env = dict(os.environ)
    env["DIM_BIN"] = str(stub)
    env["DIM_TIMEOUT_SECONDS"] = "1"
    proc = subprocess.run([sys.executable, str(COLLECTOR), "--no-tokens"],
                          capture_output=True, text=True, env=env, timeout=60)
    self.assertIn("timed out after 1s", json.loads(proc.stdout)["error"])

  # ------------------------------------------------------------- local usage

  def build_ledger(self, **kwargs) -> Path:
    return build_usage_db(
      self.usage_db,
      kwargs.get("days", [
        {
          "day": day_key(0),
          "totalTokens": 37_945_273,
          "inputTokens": 37_749_629,
          "outputTokens": 195_644,
          "cacheReadTokens": 37_469_312,
          "estimatedCostUsd": 0.2809,
          "runCount": 7,
          "sessionCount": 3,
        },
        {
          "day": day_key(-1),
          "totalTokens": 1_000_000,
          "estimatedCostUsd": 0.01,
          "runCount": 2,
          "sessionCount": 1,
        },
      ]),
      runs=kwargs.get("runs", [
        {
          "modelId": "deepseek-v4.1-flash",
          "inputTokens": 37_749_629,
          "outputTokens": 195_644,
          "totalTokens": 37_945_273,
          "cacheReadTokens": 37_469_312,
          "cacheWriteTokens": -1,
          "cost": json.dumps({"totalCostUsd": 0.202283742}),
          "sessionId": "sess_1",
        },
        {
          "modelId": "deepseek-v4.1-flash",
          "inputTokens": 3317592,
          "outputTokens": 26488,
          "totalTokens": 3344080,
          "cacheReadTokens": 3233664,
          "cost": json.dumps({"totalCostUsd": 0.0394557584}),
          "sessionId": "sess_2",
        },
        {
          "modelId": "glm-5.3",
          "inputTokens": 300000,
          "outputTokens": 20000,
          "totalTokens": 320000,
          "cacheReadTokens": 100000,
          "cost": "0.02",
          "sessionId": "sess_1",
        },
      ]),
    )

  def test_ledger_reports_today_and_window(self) -> None:
    self.build_ledger()
    snapshot, code = self.run_collector()
    self.assertEqual(code, 0)
    tokens = snapshot["tokens"]
    self.assertEqual(tokens["source"], "dim")
    self.assertEqual(tokens["database"], str(self.usage_db))
    self.assertEqual(tokens["today"], day_key(0))
    self.assertEqual(tokens["todayTotal"], 37_945_273)
    self.assertEqual(tokens["todayRuns"], 7)
    self.assertEqual(tokens["todaySessions"], 3)
    self.assertEqual(tokens["todayCostUsd"], 0.2809)
    self.assertEqual(tokens["windowDays"], 30)
    self.assertEqual(tokens["windowTotal"], 38_945_273)
    self.assertEqual(tokens["windowRuns"], 9)
    self.assertEqual(tokens["windowSessions"], 4)
    self.assertEqual(tokens["activeDays"], 2)
    self.assertEqual(tokens["recentTotal"], 38_945_273)
    self.assertEqual(len(tokens["days"]), 7)
    # Days with no rows still occupy their slot in the week.
    self.assertEqual(tokens["days"][0]["total"], 0)
    self.assertEqual(tokens["days"][-1]["date"], day_key(0))
    self.assertEqual(tokens["days"][-1]["costUsd"], 0.2809)

  def test_ledger_groups_by_model_and_splits_cache_out_of_input(self) -> None:
    self.build_ledger()
    snapshot, _ = self.run_collector()
    models = snapshot["tokens"]["byModel"]
    self.assertEqual(models[0]["model"], "deepseek-v4.1-flash")
    self.assertEqual(models[0]["runs"], 2)
    self.assertEqual(models[0]["total"], 37_945_273 + 3_344_080)
    self.assertEqual(models[0]["cacheReadTokens"], 37_469_312 + 3_233_664)
    # A negative cache-write count is "not recorded", never a subtraction.
    self.assertEqual(models[0]["cacheWriteTokens"], 0)
    self.assertEqual(
      models[0]["uncachedInputTokens"],
      (37_749_629 - 37_469_312) + (3_317_592 - 3_233_664))
    self.assertAlmostEqual(models[0]["costUsd"], 0.2417, places=3)
    self.assertEqual(models[0]["sessions"], 2)
    self.assertEqual(models[1]["model"], "glm-5.3")
    self.assertAlmostEqual(models[1]["costUsd"], 0.02, places=4)
    self.assertEqual(snapshot["tokens"]["byProvider"], {"dimcode-api-oauth": 37_945_273 + 3_344_080 + 320_000})

  def test_ledger_window_days_flag_shortens_the_window(self) -> None:
    self.build_ledger()
    snapshot, _ = self.run_collector("--window-days", "1")
    self.assertEqual(snapshot["tokens"]["windowDays"], 1)
    self.assertEqual(snapshot["tokens"]["windowTotal"], 37_945_273)
    self.assertEqual(snapshot["tokens"]["activeDays"], 1)
    # The week chart keeps its seven rows whatever the summary window is.
    self.assertEqual(len(snapshot["tokens"]["days"]), 7)

  def test_missing_ledger_still_reports_credits(self) -> None:
    snapshot, code = self.run_collector(usage_db=self.root / "nope.sqlite")
    self.assertEqual(code, 0)
    self.assertTrue(snapshot["ok"])
    self.assertIsNone(snapshot["tokens"])
    self.assertIn("usage database was not found", snapshot["tokenError"])
    self.assertEqual(snapshot["credits"]["used"], 5198)

  def test_unreadable_ledger_still_reports_credits(self) -> None:
    broken = self.root / "broken.sqlite"
    broken.write_bytes(b"this is not a database")
    snapshot, code = self.run_collector(usage_db=broken)
    self.assertEqual(code, 0)
    self.assertTrue(snapshot["ok"])
    self.assertIsNone(snapshot["tokens"])
    self.assertIn("cannot read", snapshot["tokenError"])
    self.assertEqual(snapshot["credits"]["used"], 5198)

  def test_database_without_usage_tables_is_reported(self) -> None:
    empty = self.root / "empty.sqlite"
    conn = sqlite3.connect(empty)
    conn.execute("create table unrelated (id integer)")
    conn.commit()
    conn.close()
    snapshot, code = self.run_collector(usage_db=empty)
    self.assertEqual(code, 0)
    self.assertIsNone(snapshot["tokens"])
    self.assertIn("cannot read", snapshot["tokenError"])

  def test_no_tokens_flag_skips_the_ledger(self) -> None:
    self.build_ledger()
    snapshot, _ = self.run_collector("--no-tokens")
    self.assertIsNone(snapshot["tokens"])

  def test_dimcode_home_env_points_at_the_ledger(self) -> None:
    self.build_ledger()
    env = dict(os.environ)
    env["DIM_BIN"] = str(self.settings)
    env["DIMCODE_HOME"] = str(self.root)
    proc = subprocess.run([sys.executable, str(COLLECTOR)],
                          capture_output=True, text=True, env=env, timeout=60)
    snapshot = json.loads(proc.stdout)
    self.assertEqual(snapshot["tokens"]["database"], str(self.usage_db))

  # --------------------------------------------------------------- contract

  def test_snapshot_keys_the_panel_binds_to(self) -> None:
    """The panel reads these paths directly; renaming one breaks the widget.

    tests/test_model.js asserts the same shape from the panel's side, against
    a fixture. This test asserts it from the collector's side, against real
    output, so the two fixtures cannot drift apart unnoticed.
    """
    self.build_ledger()
    snapshot, _ = self.run_collector()

    def path(root, dotted):
      current = root
      for part in dotted.split("."):
        self.assertIsInstance(current, dict, dotted)
        self.assertIn(part, current, dotted)
        current = current[part]
      return current

    for dotted in [
      "schemaVersion", "generatedAt", "dimPath", "dimFound", "ok", "error",
      "accountId", "compactModel",
      "subscription.status", "subscription.cancelAtPeriodEnd",
      "plan.name", "plan.priceAmount", "plan.currency", "plan.interval", "plan.provider",
      "credits.total", "credits.used", "credits.remaining", "credits.usedFraction",
      "term.endAt",
      "models.count",
      "tokens.source", "tokens.database", "tokens.windowDays",
      "tokens.today", "tokens.todayTotal", "tokens.todayRuns", "tokens.todaySessions",
      "tokens.todayCostUsd", "tokens.days", "tokens.windowTotal", "tokens.windowRuns",
      "tokens.windowSessions", "tokens.windowCostUsd", "tokens.activeDays",
      "tokens.byModel", "tokens.byProvider",
    ]:
      path(snapshot, dotted)

    self.assertEqual(snapshot["tokens"]["days"][0]["date"] < snapshot["tokens"]["days"][-1]["date"], True)
    self.assertIsInstance(snapshot["features"], list)
    for key in ["key", "label", "unit", "allowance", "used", "remaining", "usedFraction", "periodEnd"]:
      self.assertIn(key, snapshot["features"][0])
    for key in ["date", "total", "runs", "sessions", "costUsd"]:
      self.assertIn(key, snapshot["tokens"]["days"][6])
    for key in ["model", "provider", "inputTokens", "outputTokens", "total",
                "cacheReadTokens", "cacheWriteTokens", "uncachedInputTokens",
                "runs", "costUsd", "sessions"]:
      self.assertIn(key, snapshot["tokens"]["byModel"][0])

  def test_print_path_lists_both_sources(self) -> None:
    self.build_ledger()
    proc = subprocess.run([sys.executable, str(COLLECTOR), "--print-path", "--usage-db", str(self.usage_db)],
                          capture_output=True, text=True,
                          env={**os.environ, "DIM_BIN": str(self.settings)}, timeout=60)
    payload = json.loads(proc.stdout)
    self.assertEqual(payload["dim"], str(self.settings))
    self.assertEqual(payload["usageDatabase"], str(self.usage_db))

  def test_print_path_is_silent_when_missing(self) -> None:
    env = dict(os.environ)
    env["DIM_BIN"] = str(self.root / "absent")
    proc = subprocess.run([sys.executable, str(COLLECTOR), "--print-path"],
                          capture_output=True, text=True, env=env, timeout=60)
    self.assertEqual(proc.returncode, 1)


class RealDatabaseTestCase(unittest.TestCase):
  """One integration read of the machine's own ledger, when there is one."""

  def test_real_ledger_if_present(self) -> None:
    db = Path(os.environ.get("DIMCODE_HOME") or (Path.home() / ".dimcode" / "v2")) / "dimcode.sqlite"
    if not db.is_file():
      self.skipTest("no dim usage database on this machine")
    proc = subprocess.run([sys.executable, str(COLLECTOR), "--usage-db", str(db)],
                          capture_output=True, text=True, timeout=60)
    snapshot = json.loads(proc.stdout)
    tokens = snapshot["tokens"]
    self.assertIsNotNone(tokens, snapshot.get("tokenError"))
    self.assertEqual(tokens["database"], str(db))
    self.assertEqual(len(tokens["days"]), 7)
    self.assertGreaterEqual(tokens["windowTotal"], tokens["todayTotal"])
    for day in tokens["days"]:
      self.assertGreaterEqual(day["total"], 0)


class HelperTestCase(unittest.TestCase):
  """Unit coverage for the pure helpers, imported straight from the script."""

  @classmethod
  def setUpClass(cls) -> None:
    import importlib.machinery
    import importlib.util

    # Importing the extensionless script would otherwise leave a bytecode cache
    # beside it, inside the plugin folder.
    sys.dont_write_bytecode = True
    loader = importlib.machinery.SourceFileLoader("dim_usage", str(COLLECTOR))
    spec = importlib.util.spec_from_loader("dim_usage", loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cls.module = module

  def test_local_day_accepts_iso_epoch_and_junk(self) -> None:
    local_day = self.module.local_day
    expected = datetime.fromtimestamp(1789530844).strftime("%Y-%m-%d")
    self.assertEqual(local_day(1789530844), expected)
    self.assertEqual(local_day(1789530844000), expected)
    self.assertEqual(local_day("2026-09-16T12:00:00.000Z"),
                     datetime.fromisoformat("2026-09-16T12:00:00+00:00").astimezone().strftime("%Y-%m-%d"))
    self.assertRegex(local_day("nonsense-timestamp"), r"^\d{4}-\d{2}-\d{2}$")
    self.assertRegex(local_day(None), r"^\d{4}-\d{2}-\d{2}$")

  def test_day_sequence_ends_today(self) -> None:
    sequence = self.module.day_sequence(7)
    self.assertEqual(len(sequence), 7)
    self.assertEqual(sequence[-1], datetime.now().strftime("%Y-%m-%d"))
    ordered = sorted(sequence)
    self.assertEqual(sequence, ordered)

  def test_number_tolerates_strings_and_negatives(self) -> None:
    number = self.module.number
    self.assertEqual(number("12"), 12)
    self.assertEqual(number(12.6), 13)
    self.assertEqual(number(-5), 0)
    self.assertEqual(number(None), 0)
    self.assertEqual(number("abc"), 0)

  def test_money_rounds_and_clamps(self) -> None:
    money = self.module.money
    self.assertEqual(money("0.2809032822"), 0.280903)
    self.assertEqual(money(-1), 0.0)
    self.assertEqual(money(None), 0.0)
    self.assertEqual(money("abc"), 0.0)

  def test_parse_cost_reads_json_blobs_and_plain_numbers(self) -> None:
    parse = self.module.parse_cost
    self.assertAlmostEqual(parse('{"inputCostUsd":0.1,"totalCostUsd":0.202283742}'), 0.202284, places=6)
    self.assertEqual(parse("0.02"), 0.02)
    self.assertEqual(parse(None), 0.0)
    self.assertEqual(parse("{broken"), 0.0)

  def test_read_json_string_passes_dicts_through(self) -> None:
    read = self.module.read_json_string
    self.assertEqual(read('{"a": 1}'), {"a": 1})
    self.assertEqual(read({"a": 1}), {"a": 1})
    self.assertEqual(read(""), {})
    self.assertEqual(read("{broken"), {})
    self.assertEqual(read("[1,2]"), {})

  def test_normalize_credits_survives_an_empty_payload(self) -> None:
    credits = self.module.normalize_credits({}, {})
    self.assertEqual(credits["total"], 0)
    self.assertEqual(credits["remaining"], 0)
    self.assertEqual(credits["usedFraction"], 0.0)

  def test_resolve_dim_prefers_a_runnable_override(self) -> None:
    with tempfile.TemporaryDirectory() as temp:
      stub = write_stub(Path(temp) / "dim", "exit 0\n")
      os.environ["DIM_BIN"] = str(stub)
      try:
        path, error = self.module.resolve_dim()
      finally:
        del os.environ["DIM_BIN"]
      self.assertEqual(path, str(stub))
      self.assertEqual(error, "")

  def test_resolve_usage_db_reports_where_it_looked(self) -> None:
    path, error = self.module.resolve_usage_db("/nonexistent/dimcode.sqlite")
    self.assertEqual(path, "")
    self.assertIn("dimcode.sqlite", error)


if __name__ == "__main__":
  unittest.main(verbosity=2)

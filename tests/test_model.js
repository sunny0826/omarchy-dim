const assert = require("assert")
const { load } = require("./load")

const model = load("Model.js")

// A snapshot shaped exactly like scripts/dim-usage prints one, so the tests
// fail if the collector's contract and the panel's expectations drift apart.
// The token half is Dim's own ledger: per-day totals and per-run model detail.
const SNAPSHOT = {
  schemaVersion: 1,
  generatedAt: "2026-09-16T05:22:04Z",
  dimPath: "/usr/local/bin/dim",
  dimFound: true,
  ok: true,
  error: "",
  accountId: 2039,
  subscription: { id: 3099, status: "active", kind: "plan", line: "dimcode", cancelAtPeriodEnd: false },
  plan: {
    name: "Pro套餐",
    description: "估约 6000 次对话",
    type: "subscription",
    priceAmount: 29900,
    currency: "CNY",
    interval: "month",
    provider: "alipay"
  },
  credits: {
    total: 48000,
    used: 5198,
    remaining: 42802,
    addonTotal: 0,
    usedFraction: 0.108292,
    remainingFraction: 0.891708,
    expiresAt: "2026-10-13T12:33:46.906Z",
    status: "active"
  },
  term: {
    startAt: "2026-09-13T12:33:46.906Z",
    endAt: "2026-10-13T12:33:46.906Z",
    windowResetsAvailable: 0,
    fullResetsAvailable: 0,
    status: "active"
  },
  features: [
    {
      key: "web_search",
      label: "Web search",
      unit: "call",
      allowance: 2400,
      used: 0,
      remaining: 2400,
      unlimited: false,
      usedFraction: 0,
      periodEnd: "2026-10-13T12:33:46.906Z"
    }
  ],
  models: {
    count: 10,
    names: ["DeepSeek-V4-Flash", "glm-5.3"],
    compactModel: "deepseek-v4-flash",
    remoteControlEnabled: true
  },
  compactModel: "deepseek-v4.1-flash",
  tokens: {
    source: "dim",
    database: "/home/user/.dimcode/v2/dimcode.sqlite",
    windowDays: 30,
    today: "2026-09-16",
    todayTotal: 37945273,
    todayRuns: 7,
    todaySessions: 3,
    todayCostUsd: 0.280904,
    days: [
      { date: "2026-09-10", total: 0, runs: 0, sessions: 0, costUsd: 0 },
      { date: "2026-09-11", total: 0, runs: 0, sessions: 0, costUsd: 0 },
      { date: "2026-09-12", total: 0, runs: 0, sessions: 0, costUsd: 0 },
      { date: "2026-09-13", total: 0, runs: 0, sessions: 0, costUsd: 0 },
      { date: "2026-09-14", total: 120000, runs: 2, sessions: 1, costUsd: 0.01 },
      { date: "2026-09-15", total: 350000, runs: 3, sessions: 1, costUsd: 0.02 },
      { date: "2026-09-16", total: 37945273, runs: 7, sessions: 3, costUsd: 0.280904 }
    ],
    recentTotal: 38425273,
    recentRuns: 12,
    recentCostUsd: 0.310904,
    windowTotal: 38425273,
    windowRuns: 12,
    windowSessions: 5,
    windowCostUsd: 0.310904,
    activeDays: 3,
    byModel: [
      {
        model: "deepseek-v4.1-flash",
        provider: "dimcode-api-oauth",
        inputTokens: 37749629,
        outputTokens: 195644,
        total: 37945273,
        cacheReadTokens: 37469312,
        cacheWriteTokens: 0,
        uncachedInputTokens: 280317,
        runs: 7,
        costUsd: 0.280904,
        sessions: 3
      },
      {
        model: "glm-5.3",
        provider: "dimcode-api-oauth",
        inputTokens: 300000,
        outputTokens: 20000,
        total: 320000,
        cacheReadTokens: 100000,
        cacheWriteTokens: 0,
        uncachedInputTokens: 200000,
        runs: 2,
        costUsd: 0.02,
        sessions: 1
      }
    ],
    byProvider: { "dimcode-api-oauth": 38265273 }
  }
}

// jsonCopy keeps each test from mutating the shared fixture.
function jsonCopy(value) {
  return JSON.parse(JSON.stringify(value))
}

// ------------------------------------------------------------------ numbers

assert.strictEqual(model.formatCount(5198), "5.2K")
assert.strictEqual(model.formatCount(48000), "48.0K")
assert.strictEqual(model.formatCount(37945273), "37.9M")
assert.strictEqual(model.formatCount(9912342), "9.9M")
assert.strictEqual(model.formatCount(0), "0")
assert.strictEqual(model.formatCount(999), "999")
assert.strictEqual(model.formatCount(undefined), "0")
assert.strictEqual(model.formatCount("nonsense"), "0")

assert.strictEqual(model.percentText(0.1083), "11%")
assert.strictEqual(model.percentText(0), "0%")
assert.strictEqual(model.percentText(1), "100%")
assert.strictEqual(model.percentText(1.5), "100%")
assert.strictEqual(model.percentText(-3), "0%")

assert.strictEqual(model.runText(1), "1 run")
assert.strictEqual(model.runText(7), "7 runs")
assert.strictEqual(model.runText(0), "0 runs")
assert.strictEqual(model.sessionText(1), "1 session")
assert.strictEqual(model.sessionText(3), "3 sessions")
assert.strictEqual(model.dayText(1), "1 active day")
assert.strictEqual(model.dayText(3), "3 active days")

assert.strictEqual(model.formatCost(0), "$0")
assert.strictEqual(model.formatCost(0.280904), "$0.28")
assert.strictEqual(model.formatCost(1.5), "$1.50")
assert.strictEqual(model.formatCost(0.0025), "$0.003")
assert.strictEqual(model.formatCost(undefined), "$0")

assert.strictEqual(model.clamp(5, 0, 1), 1)
assert.strictEqual(model.clamp(-5, 0, 1), 0)
assert.strictEqual(model.clamp(0.5, 0, 1), 0.5)

// ----------------------------------------------------------------- duration

assert.strictEqual(model.formatDuration(27 * 86400000 + 8 * 3600000), "27d 8h")
assert.strictEqual(model.formatDuration(4 * 3600000 + 5 * 60000), "4h 5m")
assert.strictEqual(model.formatDuration(12 * 60000), "12m")
assert.strictEqual(model.formatDuration(0), "now")
assert.strictEqual(model.formatDuration(-10), "now")
assert.strictEqual(model.formatDuration(30000), "1m")

const END = "2026-10-13T12:33:46.906Z"
const END_MS = new Date(END).getTime()
assert.strictEqual(model.resetMs(END, END_MS - 2 * 3600000), 2 * 3600000)
assert.strictEqual(model.resetMs("", END_MS), -1)
assert.strictEqual(model.resetMs("not a date", END_MS), -1)
assert.strictEqual(model.resetText(END, END_MS - 2 * 3600000), "Resets in 2h 0m")
assert.strictEqual(model.resetText(END, END_MS + 1000), "Resetting now")
assert.strictEqual(model.resetText("", END_MS), "")

assert.strictEqual(model.formatDate("2026-10-13T12:33:46.906Z"), "13 Oct 2026")
assert.strictEqual(model.formatDate(""), "")
assert.strictEqual(model.formatDate("nonsense"), "")

assert.strictEqual(model.dayName("2026-09-16"), "Wed")
assert.strictEqual(model.dayName("2026-09-15"), "Tue")
assert.strictEqual(model.dayName("nonsense"), "nonsense")

// --------------------------------------------------------------------- plan

assert.strictEqual(model.currencySymbol("CNY"), "¥")
assert.strictEqual(model.currencySymbol("usd"), "$")
assert.strictEqual(model.currencySymbol(""), "")
assert.strictEqual(model.currencySymbol("SEK"), "SEK ")
assert.strictEqual(model.formatPrice(29900, "CNY", "month"), "¥299/month")
assert.strictEqual(model.formatPrice(1999, "USD", "month"), "$19.99/month")
assert.strictEqual(model.formatPrice(120000, "CNY", "year"), "¥1200/year")
assert.strictEqual(model.formatPrice(0, "CNY", ""), "¥0")
assert.strictEqual(model.planMeta(SNAPSHOT.plan), "Pro套餐 · ¥299/month")
assert.strictEqual(model.planMeta(null), "")
assert.strictEqual(model.planMeta({ name: "Pro" }), "Pro")
assert.strictEqual(model.planDetail(SNAPSHOT.subscription), "Active")
assert.strictEqual(model.planDetail({ status: "past_due" }), "Past_due")
assert.strictEqual(model.planDetail({ status: "active", cancelAtPeriodEnd: true }), "Cancels at period end")
assert.strictEqual(model.planDetail(null), "")

// ------------------------------------------------------------------ credits

assert.strictEqual(model.usedPercent(SNAPSHOT.credits), 0.108292)
assert.strictEqual(model.usedPercent({ total: 100, used: 25 }), 0.25)
assert.strictEqual(model.usedPercent({ total: 0, used: 0 }), 0)
assert.strictEqual(model.usedPercent({ total: 100, used: 400 }), 1)
assert.strictEqual(model.usedPercent(null), 0)
assert.strictEqual(model.creditUsedText(SNAPSHOT.credits), "5.2K / 48.0K")
assert.strictEqual(model.creditUsedText({ total: 0 }), "")
assert.strictEqual(model.creditRemainingText(SNAPSHOT.credits), "42.8K left")
assert.strictEqual(model.creditRemainingText(null), "")

assert.strictEqual(model.alarming(SNAPSHOT), false)
assert.strictEqual(model.alarming({ ok: true, credits: { usedFraction: 0.9 } }), true)
assert.strictEqual(model.alarming({ ok: true, credits: { usedFraction: 0.5 } }, 0.4), true)
assert.strictEqual(model.alarming({ ok: false, credits: { usedFraction: 1 } }), false)
assert.strictEqual(model.alarming(null), false)

// ---------------------------------------------------------------- bar label

assert.strictEqual(model.normalizeDisplay("used"), "Used")
assert.strictEqual(model.normalizeDisplay("Icon"), "Icon")
assert.strictEqual(model.normalizeDisplay("remaining"), "Remaining")
assert.strictEqual(model.normalizeDisplay(undefined), "Remaining")
assert.strictEqual(model.normalizeDisplay("nonsense"), "Remaining")

assert.strictEqual(model.barReading(SNAPSHOT, "Remaining"), "89%")
assert.strictEqual(model.barReading(SNAPSHOT, "Used"), "11%")
assert.strictEqual(model.barReading(SNAPSHOT, "Icon"), "")
assert.strictEqual(model.barReading({ ok: false }, "Remaining"), "")
assert.strictEqual(model.barReading(null, "Remaining"), "")
assert.strictEqual(model.barGlyph(SNAPSHOT), "󰚩")
assert.strictEqual(model.barGlyph({ ok: false }), "󰀦")
assert.strictEqual(model.barGlyph(null), "󰀦")

const tooltip = model.barTooltip(SNAPSHOT, END_MS - 2 * 3600000)
assert.ok(tooltip.startsWith("Dim · 11% of 48.0K credits used"), tooltip)
assert.ok(tooltip.includes("42.8K left"), tooltip)
assert.ok(tooltip.includes("resets in 2h 0m"), tooltip)
assert.ok(tooltip.includes("today 37.9M tokens"), tooltip)
assert.ok(tooltip.includes("$0.28"), tooltip)
assert.strictEqual(model.barTooltip(null, Date.now()), "Dim · reading usage…")
assert.strictEqual(model.barTooltip({ ok: false, error: "dim CLI not found" }, Date.now()),
  "Dim · dim CLI not found")
// A failed read still names the tool rather than rendering an empty tooltip.
assert.strictEqual(model.barTooltip({ ok: false, error: "" }, Date.now()), "Dim · usage unavailable")

// ---------------------------------------------------------------- bar mark

assert.strictEqual(model.normalizeMark("mono"), "Mono")
assert.strictEqual(model.normalizeMark("color"), "Color")
assert.strictEqual(model.normalizeMark("brand"), "Color")   // former spelling
assert.strictEqual(model.normalizeMark("tint"), "Mono")     // former spelling
assert.strictEqual(model.normalizeMark("logo"), "Logo")
assert.strictEqual(model.normalizeMark(undefined), "Mono")
assert.strictEqual(model.normalizeMark("nonsense"), "Mono")
assert.strictEqual(model.markAsset("Mono"), "assets/dim-mark.svg")
assert.strictEqual(model.markAsset("Color"), "assets/dim-mark-color.svg")
assert.strictEqual(model.markAsset("Logo"), "assets/dim-logo.png")
assert.strictEqual(model.markIsTinted("Mono"), true)
assert.strictEqual(model.markIsTinted("Color"), false)
assert.strictEqual(model.markIsTinted("Logo"), false)

// -------------------------------------------------------------- usage table

const rows = model.dayRows(SNAPSHOT.tokens, new Date("2026-09-16T12:00:00").getTime())
assert.strictEqual(rows.length, 7)
assert.strictEqual(rows[6].label, "Today")
assert.strictEqual(rows[6].isToday, true)
assert.strictEqual(rows[6].fraction, 1)          // today is the peak
assert.strictEqual(rows[6].runs, 7)
assert.strictEqual(rows[6].cost, 0.280904)
assert.strictEqual(rows[5].label, "Tue")
assert.strictEqual(rows[5].isToday, false)
assert.strictEqual(rows[0].fraction, 0)
assert.strictEqual(model.dayRows(null, Date.now()).length, 0)

const models = model.modelRows(SNAPSHOT.tokens, 3)
assert.strictEqual(models.length, 2)
assert.strictEqual(models[0].label, "DeepSeek V4.1 Flash")
assert.strictEqual(models[0].fraction, 1)
assert.strictEqual(models[0].runs, 7)
assert.strictEqual(models[0].detail, "in 280.3K · out 195.6K · cache 37.5M · $0.28")
assert.strictEqual(models[1].label, "GLM 5.3")
assert.strictEqual(models[1].detail, "in 200.0K · out 20.0K · cache 100.0K · $0.02")
assert.strictEqual(model.modelRows(SNAPSHOT.tokens, 1).length, 1)
assert.strictEqual(model.modelRows(null, 3).length, 0)
assert.strictEqual(model.modelLabel("glm-5.3-flash"), "GLM 5.3 Flash")
assert.strictEqual(model.modelLabel(""), "unknown")
assert.strictEqual(model.modelLabel("gpt-6-astra"), "GPT 6 Astra")

const features = model.featureRows(SNAPSHOT.features)
assert.strictEqual(features.length, 1)
assert.strictEqual(features[0].label, "Web search")
assert.strictEqual(features[0].value, "0 / 2.4K calls")
assert.strictEqual(features[0].fraction, 0)
assert.strictEqual(features[0].endAt, "2026-10-13T12:33:46.906Z")
const unlimited = model.featureRows([{ key: "x", allowance: 0, used: 12, unlimited: true, unit: "call" }])
assert.strictEqual(unlimited[0].value, "12 used")
assert.strictEqual(model.featureRows(null).length, 0)

assert.strictEqual(model.usageSourceCaption(SNAPSHOT.tokens), "Dim's own usage ledger · dimcode-api-oauth")
assert.strictEqual(model.usageSourceCaption({ byProvider: {} }), "Dim's own usage ledger")
assert.strictEqual(model.usageSourceCaption(null), "")
// The caption names the provider with the most tokens, not the first key seen.
assert.strictEqual(model.usageSourceCaption({ byProvider: { a: 10, b: 90 } }), "Dim's own usage ledger · b")

assert.strictEqual(model.windowText(SNAPSHOT.tokens),
  "Last 30 days · 38.4M tokens · 12 runs · $0.31")
assert.strictEqual(model.windowText(null), "")
assert.strictEqual(model.modelsText(SNAPSHOT.models), "10 models")
assert.strictEqual(model.modelsText({ count: 1 }), "1 model")
assert.strictEqual(model.modelsText({ count: 0 }), "")

const now = new Date("2026-09-16T12:00:00").getTime()
assert.strictEqual(model.updatedText(now - 5000, now), "Updated just now")
assert.strictEqual(model.updatedText(now - 300000, now), "Updated 5m ago")
assert.strictEqual(model.updatedText(now - 7200000, now), "Updated 2h ago")
assert.strictEqual(model.updatedText(0, now), "")

// --------------------------------------------------------------------- help

assert.strictEqual(model.errorHelp(SNAPSHOT), "")
assert.ok(model.errorHelp({ ok: false, dimFound: false }).includes("dim command was not found"))
assert.ok(model.errorHelp({ ok: false, dimFound: true }).includes("dim usage"))

assert.strictEqual(model.usageErrorText(SNAPSHOT), "")
assert.strictEqual(model.usageErrorText({ tokenError: "cannot read dimcode.sqlite" }),
  "cannot read dimcode.sqlite")
assert.strictEqual(model.usageErrorText(null), "")

assert.strictEqual(model.fileUrlToPath("file:///home/user/.config/omarchy/plugins/sunny0826.dim/scripts/dim-usage"),
  "/home/user/.config/omarchy/plugins/sunny0826.dim/scripts/dim-usage")
assert.strictEqual(model.fileUrlToPath("/already/a/path"), "/already/a/path")
assert.strictEqual(model.fileUrlToPath("file:///tmp/a%20b"), "/tmp/a b")
assert.strictEqual(model.fileUrlToPath(undefined), "")

// The widget must never claim more usage than the ledger holds, whatever the
// API reports for the two halves.
const inconsistent = jsonCopy(SNAPSHOT)
delete inconsistent.credits.usedFraction
inconsistent.credits.total = 1000
inconsistent.credits.used = 250
assert.strictEqual(model.usedPercent(inconsistent.credits), 0.25)
assert.strictEqual(model.barReading(inconsistent, "Used"), "25%")

// ----------------------------------------------------------------- commands

const script = "/home/user/.config/omarchy/plugins/sunny0826.dim/scripts/dim-usage"
assert.deepStrictEqual(Array.from(model.usageCommand(script, {})), [script])
assert.deepStrictEqual(Array.from(model.usageCommand(script, { dimBinary: "/opt/dim" })),
  [script, "--dim-bin", "/opt/dim"])
// An empty binary path must not turn into an empty argument.
assert.deepStrictEqual(Array.from(model.usageCommand(script, { dimBinary: "" })), [script])
assert.deepStrictEqual(Array.from(model.usageCommand(script)), [script])

console.log("Model.js: all assertions passed")

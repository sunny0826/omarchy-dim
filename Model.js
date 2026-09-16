.pragma library

// Formatting and derivation for the Dim widget. Everything here is a plain
// function over plain JSON: no Qt, no QML engine globals, no I/O. That keeps
// the panel's wording and arithmetic testable in node (tests/test_model.js)
// and leaves Panel.qml with only layout.

// Nerd Font marks, checked against JetBrainsMono Nerd Font's coverage. The
// shell prefers the plugin's own logo assets; these are what it falls back to.
var GLYPH = "\u{f06a9}"        // md-robot — the agent itself
var GLYPH_WARNING = "\u{f0026}" // md-alert — shown when usage cannot be read
var SEP = " · "

// ------------------------------------------------------------------- numbers

function num(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || isNaN(n)) return fallback === undefined ? 0 : fallback
  return n
}

function clamp(value, low, high) {
  if (value < low) return low
  if (value > high) return high
  return value
}

function percentText(fraction) {
  return Math.round(clamp(num(fraction, 0), 0, 1) * 100) + "%"
}

// 5198 -> "5.2K". The same shape the first-party agents panel uses, so the
// two widgets never disagree about how big a number looks.
function formatCount(value) {
  var n = num(value, 0)
  if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
  if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
  return String(Math.round(n))
}

function runText(count) {
  var n = Math.round(num(count, 0))
  return n + (n === 1 ? " run" : " runs")
}

function sessionText(count) {
  var n = Math.round(num(count, 0))
  return n + (n === 1 ? " session" : " sessions")
}

function dayText(count) {
  var n = Math.round(num(count, 0))
  return n + (n === 1 ? " active day" : " active days")
}

// Dim's own estimate of what the recorded usage would have cost, in USD.
function formatCost(value) {
  var amount = num(value, 0)
  if (amount <= 0) return "$0"
  if (amount < 0.01) return "$" + amount.toFixed(3)
  return "$" + amount.toFixed(2)
}

function padded(value) {
  return (value < 10 ? "0" : "") + value
}

// "27d 8h", "4h 5m", "12m", "now" — the same ladder the agents panel uses.
function formatDuration(ms) {
  var remaining = num(ms, 0)
  if (!(remaining > 0)) return "now"
  var minutes = Math.floor(remaining / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

function resetMs(endIso, nowMs) {
  if (!endIso) return -1
  var end = new Date(endIso).getTime()
  if (!isFinite(end) || isNaN(end)) return -1
  return end - num(nowMs, Date.now())
}

function resetText(endIso, nowMs) {
  if (!endIso) return ""
  var end = new Date(String(endIso)).getTime()
  if (!isFinite(end) || isNaN(end)) return ""
  var ms = end - num(nowMs, Date.now())
  return ms > 0 ? "Resets in " + formatDuration(ms) : "Resetting now"
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function parseIso(value) {
  if (!value) return null
  var date = new Date(String(value))
  return isFinite(date.getTime()) ? date : null
}

function formatDate(value) {
  var date = parseIso(value)
  if (!date) return ""
  return date.getDate() + " " + MONTHS[date.getMonth()] + " " + date.getFullYear()
}

// Local calendar day of a parsed date, as "YYYY-MM-DD".
function localDateKey(date) {
  return date.getFullYear() + "-" + padded(date.getMonth() + 1) + "-" + padded(date.getDate())
}

function dayName(dateStr) {
  var date = new Date(String(dateStr) + "T00:00:00")
  if (!isFinite(date.getTime())) return String(dateStr || "")
  return WEEKDAYS[date.getDay()]
}

// ---------------------------------------------------------------------- plan

function currencySymbol(code) {
  var upper = String(code || "").toUpperCase()
  if (upper === "USD") return "$"
  if (upper === "EUR") return "\u20ac"
  if (upper === "GBP") return "\u00a3"
  if (upper === "CNY" || upper === "RMB") return "\u00a5"
  return upper === "" ? "" : upper + " "
}

// Prices arrive in minor units (29900 CNY = ¥299).
function formatPrice(amountMinor, currency, interval) {
  var amount = num(amountMinor, 0) / 100
  var text = currencySymbol(currency) + (amount === Math.round(amount) ? String(Math.round(amount)) : amount.toFixed(2))
  var cycle = String(interval || "")
  if (cycle === "month") return text + "/month"
  if (cycle === "year") return text + "/year"
  if (cycle === "week") return text + "/week"
  return text
}

// The line under the widget's name: what plan this is and what it costs.
function planMeta(plan) {
  if (!plan) return ""
  var parts = []
  if (plan.name) parts.push(String(plan.name))
  if (num(plan.priceAmount, 0) > 0) parts.push(formatPrice(plan.priceAmount, plan.currency, plan.interval))
  return parts.join(SEP)
}

function planDetail(subscription) {
  if (!subscription) return ""
  if (subscription.cancelAtPeriodEnd) return "Cancels at period end"
  var status = String(subscription.status || "")
  if (status === "") return ""
  return status.charAt(0).toUpperCase() + status.slice(1)
}

// ------------------------------------------------------------------- credits

function usedPercent(credits) {
  if (!credits) return 0
  if (isFinite(num(credits.usedFraction, NaN))) return clamp(num(credits.usedFraction, 0), 0, 1)
  var total = num(credits.total, 0)
  return total > 0 ? clamp(num(credits.used, 0) / total, 0, 1) : 0
}

function creditUsedText(credits) {
  if (!credits || num(credits.total, 0) <= 0) return ""
  return formatCount(credits.used) + " / " + formatCount(credits.total)
}

function creditRemainingText(credits) {
  if (!credits) return ""
  return formatCount(credits.remaining) + " left"
}

// A plan runs low the way a rate-limit window fills up: the last tenth lights
// the same alarm the agents panel uses.
function alarming(snapshot, threshold) {
  var cut = isFinite(num(threshold, NaN)) ? num(threshold, 0.9) : 0.9
  if (!snapshot || snapshot.ok !== true) return false
  return usedPercent(snapshot.credits) >= cut
}

// ----------------------------------------------------------------- bar label

function normalizeDisplay(value) {
  var text = String(value || "").toLowerCase()
  if (text === "used") return "Used"
  if (text === "icon") return "Icon"
  return "Remaining"
}

// What sits next to the mark in the bar. The mark itself is the image the
// plugin ships; this is only the reading beside it.
function barReading(snapshot, display) {
  if (!snapshot || snapshot.ok !== true) return ""
  var mode = normalizeDisplay(display)
  if (mode === "Icon") return ""
  var fraction = usedPercent(snapshot.credits)
  return mode === "Used" ? percentText(fraction) : percentText(1 - fraction)
}

// The mark is an image; this is the glyph to fall back to when the shell
// cannot load it, and what a vertical bar shows when there is no room.
function barGlyph(snapshot) {
  if (!snapshot || snapshot.ok !== true) return GLYPH_WARNING
  return GLYPH
}

// The bar tooltip is a single line: the host renders it as one label.
function barTooltip(snapshot, nowMs) {
  if (!snapshot) return "Dim · reading usage…"
  if (snapshot.ok !== true) return "Dim · " + (snapshot.error || "usage unavailable")
  var parts = ["Dim"]
  var credits = snapshot.credits || {}
  if (num(credits.total, 0) > 0) {
    parts.push(percentText(usedPercent(credits)) + " of " + formatCount(credits.total) + " credits used")
    parts.push(formatCount(credits.remaining) + " left")
  }
  var resets = resetText((snapshot.term || {}).endAt, nowMs)
  if (resets) parts.push(resets.toLowerCase())
  var tokens = snapshot.tokens
  if (tokens && num(tokens.todayTotal, 0) > 0) {
    parts.push("today " + formatCount(tokens.todayTotal) + " tokens")
    parts.push(formatCost(tokens.todayCostUsd))
  }
  return parts.join(SEP)
}

// -------------------------------------------------------------- token tables

// Rows scale to the busiest day in the window, the way the agents panel does,
// so a quiet week still shows its shape.
function dayRows(tokens, nowMs) {
  var rows = []
  if (!tokens || !tokens.days) return rows
  var today = localDateKey(new Date(num(nowMs, Date.now())))
  var peak = 0
  for (var i = 0; i < tokens.days.length; i++) peak = Math.max(peak, num(tokens.days[i].total, 0))
  for (var j = 0; j < tokens.days.length; j++) {
    var day = tokens.days[j]
    var total = num(day.total, 0)
    rows.push({
      date: String(day.date || ""),
      label: String(day.date || "") === today ? "Today" : dayName(day.date),
      isToday: String(day.date || "") === today,
      total: total,
      runs: num(day.runs, 0),
      cost: num(day.costUsd, 0),
      fraction: peak > 0 ? total / peak : 0
    })
  }
  return rows
}

var MODEL_WORDS = {
  "gpt": "GPT",
  "glm": "GLM",
  "deepseek": "DeepSeek",
  "id": "ID",
  "ai": "AI",
  "v": "V",
  "dim": "Dim"
}

// "gpt-6-astra" reads better than "gpt-6-astra"; the raw id stays available in
// the tooltip for anyone who wants to paste it into a config.
function modelLabel(id) {
  var text = String(id || "").trim()
  if (text === "") return "unknown"
  var parts = text.split(/[-_]/)
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var word = parts[i]
    if (word === "") continue
    var lower = word.toLowerCase()
    if (MODEL_WORDS[lower]) out.push(MODEL_WORDS[lower])
    else out.push(lower.charAt(0).toUpperCase() + lower.slice(1))
  }
  return out.join(" ")
}

// ----------------------------------------------------------------- bar mark
//
// The bar shows the project's mark, monochrome by default so it reads as part
// of the bar rather than as a badge next to it; the brand colours and the full
// app icon stay available. assets/ is generated from the published logo (see
// README).

// The bar's convention is a monochrome mark; the shell's own tray does the
// same thing, colorizing system icons with the bar's foreground, which is why
// Mono works on light and dark themes from one asset instead of shipping a
// second file per surface.
function normalizeMark(value) {
  var text = String(value || "").toLowerCase()
  if (text === "color" || text === "brand" || text === "colour") return "Color"
  if (text === "logo" || text === "icon") return "Logo"
  return "Mono"
}

function markAsset(mode) {
  var mark = normalizeMark(mode)
  if (mark === "Logo") return "assets/dim-logo.png"
  if (mark === "Color") return "assets/dim-mark-color.svg"
  return "assets/dim-mark.svg"
}

function markIsTinted(mode) {
  // The white mark is drawn through the shell's colorization, so it takes the
  // bar's foreground colour — white on a dark bar, dark on a light one.
  return normalizeMark(mode) === "Mono"
}

// ------------------------------------------------------------------- usage
//
// Dim keeps its own ledger, so the panel says so: these numbers come from the
// CLI's database, not from another agent's session store.

function modelRows(tokens, limit) {
  var rows = []
  if (!tokens || !tokens.byModel) return rows
  var peak = 0
  for (var i = 0; i < tokens.byModel.length; i++) peak = Math.max(peak, num(tokens.byModel[i].total, 0))
  var max = Math.max(1, Math.round(num(limit, 3)))
  for (var j = 0; j < tokens.byModel.length && rows.length < max; j++) {
    var entry = tokens.byModel[j]
    var total = num(entry.total, 0)
    var cache = num(entry.cacheReadTokens, 0) + num(entry.cacheWriteTokens, 0)
    rows.push({
      id: String(entry.model || ""),
      label: modelLabel(entry.model),
      total: total,
      runs: num(entry.runs, 0),
      fraction: peak > 0 ? total / peak : 0,
      detail: "in " + formatCount(entry.uncachedInputTokens) + SEP
        + "out " + formatCount(entry.outputTokens) + SEP
        + "cache " + formatCount(cache) + SEP
        + formatCost(entry.costUsd)
    })
  }
  return rows
}

function featureRows(features) {
  var rows = []
  if (!features) return rows
  for (var i = 0; i < features.length; i++) {
    var feature = features[i]
    var allowance = num(feature.allowance, 0)
    var used = num(feature.used, 0)
    rows.push({
      key: String(feature.key || ""),
      label: String(feature.label || feature.key || ""),
      used: used,
      allowance: allowance,
      unit: String(feature.unit || ""),
      unlimited: feature.unlimited === true,
      fraction: feature.unlimited ? 0 : (allowance > 0 ? clamp(used / allowance, 0, 1) : 0),
      value: feature.unlimited
        ? formatCount(used) + " used"
        : formatCount(used) + " / " + formatCount(allowance) + (feature.unit ? " " + feature.unit + "s" : ""),
      endAt: String(feature.periodEnd || "")
    })
  }
  return rows
}

// Says where the token numbers come from and which provider served them, so a
// half-read ledger is never mistaken for a small one.
function usageSourceCaption(tokens) {
  if (!tokens) return ""
  var provider = ""
  var providers = tokens.byProvider || {}
  for (var key in providers) {
    if (provider === "" || num(providers[key], 0) > num(providers[provider], 0)) provider = key
  }
  var parts = ["Dim's own usage ledger"]
  if (provider !== "") parts.push(provider)
  return parts.join(SEP)
}

function windowText(tokens) {
  if (!tokens) return ""
  var days = num(tokens.windowDays, 30)
  return "Last " + days + " days" + SEP + formatCount(tokens.windowTotal) + " tokens"
    + SEP + runText(tokens.windowRuns) + SEP + formatCost(tokens.windowCostUsd)
}

function modelsText(models) {
  if (!models) return ""
  var count = num(models.count, 0)
  if (count <= 0) return ""
  return count + (count === 1 ? " model" : " models")
}

function updatedText(fetchedAtMs, nowMs) {
  var at = num(fetchedAtMs, 0)
  if (at <= 0) return ""
  var seconds = Math.max(0, Math.round((num(nowMs, Date.now()) - at) / 1000))
  if (seconds < 45) return "Updated just now"
  if (seconds < 3600) return "Updated " + Math.round(seconds / 60) + "m ago"
  return "Updated " + Math.round(seconds / 3600) + "h ago"
}

// --------------------------------------------------------------------- help

function errorHelp(snapshot) {
  if (!snapshot || snapshot.ok === true) return ""
  if (snapshot.dimFound === false) {
    return "The dim command was not found. Install the Dim CLI, or point this widget at it in its settings."
  }
  return "Run `dim usage` in a terminal to see the same error the widget is hitting."
}

// ---------------------------------------------------------------- commands

// The one command the widget runs. Built here so the flags are covered by
// tests instead of buried in QML.
function usageCommand(scriptPath, options) {
  var opts = options || {}
  var command = [String(scriptPath)]
  if (opts.dimBinary) command.push("--dim-bin", String(opts.dimBinary))
  return command
}

// Non-fatal problems with the local half: the panel keeps drawing credits and
// says why the tokens are missing.
function usageErrorText(snapshot) {
  if (!snapshot) return ""
  return String(snapshot.tokenError || "")
}

function fileUrlToPath(url) {
  var text = String(url || "")
  if (text.indexOf("file://") === 0) text = text.slice(7)
  try {
    return decodeURIComponent(text)
  } catch (error) {
    return text
  }
}

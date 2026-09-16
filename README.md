# Dim

DimAgent usage, in the Omarchy bar and one click deeper.

The widget is a window onto the subscription the `dim` CLI is signed in to:
the credits the plan granted and how many are left, when the term resets, the
feature allowances that ride along with it (web search today, whatever the
plan adds later), and what Dim itself has spent on this machine. It is a
display — it never spends, changes, or cancels anything.

```
[logo] 89%       bar: remaining credit share, urgent when the plan runs low
```

The bar shows the Dim logo: the mark in its own green by default, the same
mark tinted with the theme's foreground, or the full app icon — see
`barMark` below. Assets live in `assets/` and are generated from the published
logo, never hand-edited.

## Panel

- **Hero** — the Dim logo, the plan it runs on, and what that plan costs
  ("Pro套餐 · ¥299/month"). A subscription that is cancelling or past due says
  so here instead of hiding behind a percentage.
- **Credits** — used against granted, the used bar, what is left, and the
  reset countdown with the date the term ends.
- **Allowances** — one meter per plan feature that has its own budget, with
  the same reset countdown.
- **Local usage** — what Dim itself recorded: today's tokens with runs,
  sessions and estimated cost, one bar per day for the last week scaled to the
  busiest day, the rolling window with active days, and the top three models
  with their uncached input / output / cache split and cost on hover.
- **Plan** — status, price, billing provider, how many models the plan opens
  up, the compact model in use, and the account id.
- **Footer** — when the numbers were last read, plus the key hints.

Keyboard: `r` refreshes, `esc` closes, `↑`/`↓` scroll, `←`/`→` hands off to
the neighbouring bar panel. On the bar icon: left click opens, right or middle
click refreshes without opening.

## Data

Two halves, both of them Dim's own, merged into one snapshot by
[`scripts/dim-usage`](scripts/dim-usage):

| Half | Where it comes from | What it carries |
|---|---|---|
| Subscription | `dim usage --json` | plan, price, credit ledger, term end, feature meters, model access |
| Local usage | Dim's database, `~/.dimcode/v2/dimcode.sqlite` | `usage_daily_stats` for per-day totals, `usage_run_stats` for per-model, per-run detail and cost |

The local half deliberately does **not** read `~/.codex` (or any other agent's
session store): the Dim CLI and Codex share session files on some machines, so
replaying those would report Codex usage as Dim's. Dim keeps its own
accounting, and that is what the panel shows — tokens, runs, sessions, and
Dim's own estimated cost, attributed by the provider and model that served the
run. The database is opened read-only, and if the CLI holds it in a way SQLite
refuses to open, the collector reads a copy instead, so a running agent never
blocks the widget.

The collector runs the CLI the user already has instead of talking to an API,
so credentials never leave `dim` and nothing here needs to know about them.
Discovery is deliberately stubborn — the shell that hosts the bar does not
always inherit the PATH a terminal has (mise installs `dim` under a versioned
node prefix), so `scripts/dim-usage` tries `--dim-bin`, `DIM_BIN`, `PATH`,
`~/.local/share/mise/shims`, every mise node install, `~/.local/bin`,
`~/.npm-global/bin`, and the usual system prefixes, in that order. A single
`dim usage` that takes longer than 30 seconds is killed and reported, so a
stalled network cannot leave the widget spinning.

Nothing is written anywhere: the collector only reads, and the widget holds its
last snapshot in memory.

Failure is visible rather than silent. If `dim` cannot be found the widget
leaves the bar entirely, because a machine without the CLI has nothing to
report. If the CLI is there but answers with an error — signed out, offline,
an expired plan — the bar keeps the icon with an alert mark and the panel
shows the CLI's own message plus the one thing to try next. The two halves fail
independently: a missing or unreadable usage database costs the local section
its numbers and says so, while credits still draw. A read that never answers is
dropped and reported: `dim usage` gets 30 seconds, and the collector gets 45
before the widget gives up on it.

## Settings

Set inline on the widget's entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "sunny0826.dim",
  "refreshIntervalSec": 120,
  "barDisplay": "Remaining",
  "barMark": "Brand",
  "dimBinary": ""
}
```

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `120` | How often the CLI and the usage database are read. |
| `barDisplay` | `Remaining` | `Remaining`, `Used`, or `Icon` (logo only). A vertical bar always shows the logo alone. |
| `barMark` | `Brand` | `Brand` (the mark in its own green), `Tint` (the mark in the bar's foreground), or `Logo` (the full app icon). |
| `dimBinary` | `""` | Absolute path to `dim`, for machines where discovery fails. |

`scripts/dim-usage` can also be run by hand — it is the same JSON the panel
draws:

```bash
scripts/dim-usage --pretty              # the full snapshot
scripts/dim-usage --window-days 7       # shorten the local-usage window
scripts/dim-usage --dim-bin /opt/dim    # point it at a specific CLI
scripts/dim-usage --usage-db ~/.dimcode/v2/dimcode.sqlite
scripts/dim-usage --timeout 60          # allow a slower `dim usage`
scripts/dim-usage --print-path          # where it found the CLI and the database
```

`DIM_BIN`, `DIMCODE_HOME`, and `DIM_TIMEOUT_SECONDS` are the environment
equivalents of `--dim-bin`, the data directory that holds `dimcode.sqlite`,
and `--timeout`.

## Requirements

- **Omarchy** with the Quickshell shell (`omarchy version`; developed against
  4.x). The widget is an ordinary `bar-widget` plugin: no first-party files
  are patched, nothing is installed system-wide, and no elevated privileges are
  ever needed.
- **The Dim CLI**, signed in. It is not in the Arch repositories — install it
  the way Dim ships it (`npm i -g dimcode`, or whatever the project documents),
  then run `dim auth login` once. `omarchy plugin enable` cannot do this for
  you, because the widget never handles credentials itself.
- Optionally, `node` and `python3` for the tests. The widget itself only needs
  `/usr/bin/python3`, which Arch always has.

`dim usage` needs the network; that is the CLI's business, not the widget's.
With no `dim` on the machine the widget hides itself rather than showing a
dead icon. See [Troubleshooting](#troubleshooting) if the CLI is there but the
widget shows an alert mark.

## Install

From a git checkout (the marketplace's one-liner):

```bash
omarchy plugin add https://github.com/sunny0826/omarchy-dim.git --enable
```

The installer clones into `~/.config/omarchy/plugins/sunny0826.dim/`, validates
the manifest, and (with `--enable`) places the widget in the bar's right
section. Without `--enable` it lands disabled, so the code can be read first —
plugins run unsandboxed inside `omarchy-shell`, as the installer warns.

Already have the directory (a clone you maintain yourself):

```bash
omarchy plugin validate ~/.config/omarchy/plugins/sunny0826.dim
omarchy plugin enable sunny0826.dim
omarchy bar move sunny0826.dim --section right   # optional; the right section is the default
```

Updating a git install is `omarchy plugin update sunny0826.dim`; it
fast-forwards, so this repository's default branch only ever gains commits.

### Remove

```bash
omarchy plugin remove sunny0826.dim     # or: omarchy plugin disable sunny0826.dim
```

`disable` takes the widget out of the bar and leaves the files; `remove`
deletes the directory as well. Nothing else is written anywhere — the widget
keeps no state of its own, so there is nothing left to clean up afterwards
except the optional render cache in `~/.cache/omarchy-dim-check/`, if you ran the
development targets.

## Security

- The widget runs exactly one external command: `dim usage --json`, through
  `scripts/dim-usage` (Python, standard library only, argv arrays, no shell).
- It reads credentials never, and writes nowhere. The credit figures come from
  the CLI; the local-usage figures come from Dim's own database, opened
  **read-only** (and copied to a temporary file if the CLI holds it locked).
- No raised privileges, no package manager, no systemd, no daemon, no
  background service.
- The `dimBinary` setting runs whatever path it is given, so only set it to a
  `dim` you trust; leaving it empty lets the collector find the CLI itself.

## Troubleshooting

The bar icon is an alert mark and shows no percentage: the widget could not
read usage. Ask it what it thinks, instead of guessing:

```bash
quickshell ipc -p /usr/share/omarchy/shell call sunny0826.dim status
# ok=true reading=87% mark=assets/dim-mark-color.svg credits=6120/48000 ...
# ok=false ... error="dim CLI not found"
quickshell ipc -p /usr/share/omarchy/shell call sunny0826.dim refresh
quickshell ipc -p /usr/share/omarchy/shell call sunny0826.dim toggle   # open the panel
```

`omarchy-shell shell call sunny0826.dim ...` will *not* work: the shell only routes
`call` to panel, overlay, and menu plugins (`callIfLoaded`), and this is a bar
widget. The panel body's own error card says the same thing as `status`, and
the shell log carries a warning whenever a read fails.

Editing the plugin's files does **not** reliably replace the widget already
mounted in the bar — the shell re-reads the plugin registry and logs
`Local plugin changed, reloading: sunny0826.dim`, but the live instance can keep
running the code it was compiled with. If a change does not show up, restart
the shell:

```bash
omarchy restart shell        # rebuilds every bar widget from the current files
```

## Development

```bash
make test        # node tests for Model.js, python tests for the collector
make qml-check   # qmllint against the shell's own UI kit
make probe       # load the real QML against live data and print what it derived
make render      # draw the real bar button and panel into ~/.cache/omarchy-dim-check
make preview     # compose preview.png (the listing image) from those renders
make assets      # rebuild assets/ from the published logo
make validate    # manifest schema + all of the above
```

`qmllint` still reports two classes of warning that this plugin cannot fix:
`bar` and `Style.font` / `Style.spacing` are typed `QtObject` by the shell,
so member lookups on them cannot be verified statically, and Quickshell's
`Process.onExited` carries a `QProcess::ExitStatus` parameter qmllint has no
import for. Every other warning is treated as a bug.

Beyond the tests, the widget is exercised by loading the real QML files into a
throwaway quickshell instance with a stub bar object (`tests/render/`), which is
how the error, vertical-bar, logo-mode, and refresh paths were checked without
touching the running shell:

- `make probe` prints what the widget derived from a live snapshot — credits,
  the usage database it read, the panel's row counts, alarm state.
- `make render` draws the real bar button and panel body to
  `~/.cache/omarchy-dim-check/*.png`. Add `HARNESS_MARK=Color` (or `Logo`) and
  `HARNESS_DISPLAY=Used` to render those variants. Needs a Wayland session;
  the window it opens *is* the render.
- `make preview` runs both renders and composes [`preview.png`](preview.png)
  — the image a marketplace listing shows — from them, on the active theme's
  colours. It is a build product: regenerate it rather than editing it.

## Layout of the source

| File | Role |
|---|---|
| `Panel.qml` | Bar button, popup, and every piece of layout. The plugin's entry point. |
| `Usage.qml` | Owns the one process and the refresh timer; holds the snapshot. |
| `Model.js` | Wording, units, and arithmetic — pure functions, no Qt, testable in node. |
| `scripts/dim-usage` | Runs `dim usage --json`, reads Dim's usage database, prints one JSON snapshot. |
| `scripts/build-mark-assets` | Rebuilds `assets/` from the published logo. Pure stdlib. |
| `assets/dim-mark-color.svg` | The Dim mark in its own colours — the bar's default. |
| `assets/dim-mark.svg` | The same mark in white, for `barMark: Tint`. |
| `assets/dim-logo.png` | The app icon, cropped and de-margined, for the panel hero. |
| `PanelContent.qml` | The panel body on its own, so it can be rendered and checked without a popup. |
| `tests/` | `test_model.js` (node), `test_dim_usage.py` (python). |
| `tests/render/` | Throwaway quickshell configs that load the real QML for `make probe` / `make render`. |

Assets are generated, not drawn: `make assets` re-runs the generator, which
rewrites the three files above with the mark's rectangles and colours measured
out of the source logo it names. Edit the generator, not the assets.

## Credits

The Dim name and logo belong to the DimAgent project. This plugin is an
independent client of that project, not part of it, and ships under the MIT
licence in [LICENSE](LICENSE).

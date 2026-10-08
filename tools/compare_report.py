"""HTML report for compare_clap_variants.py: every file in the lists can be played with one click.

The page is one self-contained file. Audio is not copied: each ▶ button points at the original file on disk
(file:// URL), so open the report in a browser on the same Mac. Only one sound plays at a time; clicking the
playing one stops it.
"""
from __future__ import annotations

from html import escape
from pathlib import Path

STYLE = """
:root { color-scheme: light dark; --muted: #888; --line: #8884; --shared: #3a86ff22; --accent: #3a86ff; }
body { font: 14px/1.45 -apple-system, system-ui, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; }
h1 { font-size: 1.6rem; } h2 { margin-top: 2.5rem; border-bottom: 1px solid var(--line); padding-bottom: .3rem; }
h3 { margin: 1.8rem 0 .5rem; font-size: 1.05rem; } h3 small { color: var(--muted); font-weight: normal; }
table { border-collapse: collapse; width: 100%; table-layout: fixed; }
th, td { text-align: left; padding: .3rem .5rem; border-bottom: 1px solid var(--line); vertical-align: middle; }
th { color: var(--muted); font-weight: 600; } th:first-child, td.rank { width: 2.2rem; color: var(--muted); }
td.shared { background: var(--shared); }
.muted { color: var(--muted); } .facts td:first-child { width: 14rem; }
button.play { all: unset; cursor: pointer; display: flex; align-items: center; gap: .55rem; width: 100%; }
button.play .icon { flex: none; width: 1.7rem; height: 1.7rem; border-radius: 50%; background: var(--accent); color: #fff;
  display: grid; place-items: center; font-size: .7rem; }
button.play:hover .name { text-decoration: underline; }
button.play.playing .icon { background: #e63946; }
.name { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.detail { color: var(--muted); font-size: .8rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.label { min-width: 0; flex: 1; }
.muted-cell { opacity: .55; }
details { margin: 1rem 0; } summary { cursor: pointer; font-weight: 600; font-size: 1.1rem; }
.anchor { padding: .5rem; border: 1px solid var(--line); border-radius: 8px; margin-bottom: .6rem; }
"""

SCRIPT = """
const player = new Audio();
let current = null;
function stop() { player.pause(); if (current) current.classList.remove('playing'); current = null; }
player.addEventListener('ended', stop);
document.addEventListener('click', event => {
  const button = event.target.closest('button.play');
  if (!button) return;
  const wasThis = current === button;
  stop();
  if (wasThis) return;
  player.src = button.dataset.src;
  player.play().then(() => { current = button; button.classList.add('playing'); })
    .catch(() => { button.querySelector('.detail').textContent = 'could not play this file'; });
});
"""


def _player(sample: dict, score: float | None = None) -> str:
    """A play button for one library file, showing its name, length, folder and (optionally) the match score."""
    folder = str(Path(sample["rel"]).parent)
    detail = f"{sample['duration']:.1f} s" + ("" if folder == "." else f" · {folder}")
    if score is not None:
        detail += f" · score {score:.2f}"
    return (f'<button class="play" data-src="{escape(Path(sample["path"]).as_uri())}" title="{escape(sample["path"])}">'
            f'<span class="icon">▶</span><span class="label"><div class="name">{escape(sample["name"])}</div>'
            f'<div class="detail">{escape(detail)}</div></span></button>')


def _table(headers: list[str], rows: list[str]) -> str:
    """`rows` hold the <td> cells of each row, already as HTML."""
    head = "".join(f"<th>{escape(h)}</th>" for h in headers)
    return f"<table><tr>{head}</tr>" + "".join(f"<tr>{row}</tr>" for row in rows) + "</table>"


def _ranked(labels: list[str], rows: list[list[tuple[dict, float, bool]]]) -> str:
    """One row per rank, one column per model; each cell is (sample, score, also found by the current model)."""
    body = []
    for rank, cells in enumerate(rows, 1):
        tds = "".join(f'<td class="{"shared" if shared else ""}">{_player(sample, score)}</td>'
                      for sample, score, shared in cells)
        body.append(f'<td class="rank">{rank}</td>' + tds)
    return _table(["", *labels], body)


def _verdict(result: dict) -> str:
    """One model's category for a sound, with how sure it was and what came second."""
    if result["category"] is None:
        best = f'<span class="muted">Uncategorised (closest {escape(result["best"])} {result["confidence"]:.0%})</span>'
    else:
        best = f'{escape(result["category"])} <span class="muted">{result["confidence"]:.0%}</span>'
    return (f'<div class="name">{best}</div><div class="detail">then {escape(result["runner_up"])} '
            f'{result["runner_up_confidence"]:.0%}</div>')


def render(*, intro: str, facts: list[tuple[str, str]], agreement: list[str], labels: list[str],
           queries: list[dict], similar: list[dict], distribution: list[tuple], categories: list[dict]) -> str:
    """queries: {"title", "shared" (per model), "rows"}; similar: {"anchor", "rows"};
    distribution: (category, count per model...); categories: {"label", "groups"} for each non-current model, where
    a group is {"current", "other", "items": [(sample, current result, other result)]}, biggest first."""
    baseline = labels[0]
    parts = [f"<!doctype html><meta charset=utf-8><title>CLAP variants</title><style>{STYLE}</style>",
             "<h1>CLAP variants on your library</h1>", f"<p>{escape(intro)}</p>",
             "<p class=muted>Click a name to play it, click again to stop. In the lists, a highlighted cell was also "
             f"found by <b>{escape(baseline)}</b>; an unhighlighted one is new.</p>",
             '<table class="facts">', *[f"<tr><td>{escape(k)}</td><td>{escape(v)}</td></tr>" for k, v in facts],
             "</table>", "<h2>How much they agree with the current model</h2><ul>",
             *[f"<li>{escape(line)}</li>" for line in agreement], "</ul>", "<h2>Text searches</h2>"]
    for query in queries:
        parts += [f'<h3>“{escape(query["title"])}” <small>shared with {escape(baseline)}: '
                  + ", ".join(f"{escape(label)} {n} of 10" for label, n in zip(labels[1:], query["shared"]))
                  + "</small></h3>", _ranked(labels, query["rows"])]
    parts.append("<h2>Find similar</h2><p class=muted>Play the reference first, then compare what each model "
                 "considers closest.</p>")
    for item in similar:
        parts += ["<h3>Like this sound</h3>", f'<div class="anchor">{_player(item["anchor"])}</div>',
                  _ranked(labels, item["rows"])]
    parts += ["<h2>Categories</h2><p class=muted>The app's 20 categories, decided exactly as the app does it.</p>",
              _table(["Category", *labels], [f"<td>{escape(str(c[0]))}</td>" + "".join(f"<td>{n}</td>" for n in c[1:])
                                              for c in distribution])]
    for entry in categories:
        total = sum(len(g["items"]) for g in entry["groups"])
        parts.append(f"<details><summary>{escape(entry['label'])}: {total} sound{'' if total == 1 else 's'} "
                     f"categorised differently from {escape(baseline)}</summary>")
        for group in entry["groups"]:
            n = len(group["items"])
            parts += [f'<h3>{escape(baseline)}: {escape(group["current"])} → {escape(entry["label"])}: '
                      f'{escape(group["other"])} <small>{n} sound{"" if n == 1 else "s"}</small></h3>',
                      _table(["Sound", baseline, entry["label"]],
                             [f"<td>{_player(s)}</td><td>{_verdict(a)}</td><td>{_verdict(b)}</td>"
                              for s, a, b in group["items"]])]
        parts.append("</details>")
    parts.append(f"<script>{SCRIPT}</script>")
    return "\n".join(parts)

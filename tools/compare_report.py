"""HTML report for compare_embedders.py: every file in the lists can be played with one click.

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


def _comparison_table(rows: list[tuple[tuple, tuple]]) -> str:
    out = ['<table><tr><th></th><th>CLAP</th><th>EmbeddingGemma 2</th></tr>']
    for rank, (left, right) in enumerate(rows, 1):
        cells = "".join(f'<td class="{"shared" if shared else ""}">{_player(sample, score)}</td>'
                        for sample, score, shared in (left, right))
        out.append(f'<tr><td class="rank">{rank}</td>{cells}</tr>')
    out.append("</table>")
    return "".join(out)


def render(*, intro: str, facts: list[tuple[str, str]], agreement: list[str], queries: list[dict],
           similar: list[dict]) -> str:
    """queries: {"title", "shared", "total", "rows"}; similar: {"anchor", "rows"}; rows pair (sample, score, shared)."""
    parts = [f"<!doctype html><meta charset=utf-8><title>CLAP and EmbeddingGemma 2</title><style>{STYLE}</style>",
             "<h1>CLAP and EmbeddingGemma 2 on your library</h1>", f"<p>{escape(intro)}</p>",
             "<p class=muted>Click a name to play it, click again to stop. Highlighted rows were found by both models.</p>",
             '<table class="facts">',
             *[f"<tr><td>{escape(k)}</td><td>{escape(v)}</td></tr>" for k, v in facts], "</table>",
             "<h2>How much they agree</h2><ul>", *[f"<li>{escape(line)}</li>" for line in agreement], "</ul>",
             "<p class=muted>Low agreement is expected and is not a verdict: two good models can rank differently. "
             "Listen to the lists below and decide which one you would rather browse.</p>",
             "<h2>Text searches</h2>"]
    for query in queries:
        parts += [f'<h3>“{escape(query["title"])}” <small>agree on {query["shared"]} of {query["total"]}</small></h3>',
                  _comparison_table(query["rows"])]
    parts.append("<h2>Find similar</h2><p class=muted>Play the reference first, then compare what each model "
                 "considers closest.</p>")
    for item in similar:
        parts += ['<h3>Like this sound</h3>', f'<div class="anchor">{_player(item["anchor"])}</div>',
                  _comparison_table(item["rows"])]
    parts.append(f"<script>{SCRIPT}</script>")
    return "\n".join(parts)


def _verdict(result: dict) -> str:
    """One model's category for a sound, with how sure it was and what came second."""
    name = result["category"] or "Uncategorised"
    best = f'{escape(name)} <span class="muted">{result["confidence"]:.0%}</span>'
    runner_up = f'then {escape(result["runner_up"])} {result["runner_up_confidence"]:.0%}'
    if result["category"] is None:
        best = (f'<span class="muted">Uncategorised (closest {escape(result["best"])} '
                f'{result["confidence"]:.0%})</span>')
    return f'<div class="name">{best}</div><div class="detail">{runner_up}</div>'


def render_categories(*, intro: str, agreement: list[str], distribution: list[tuple[str, int, int]],
                      changes: list[tuple[str, str, int]], groups: list[dict]) -> str:
    """groups: {"clap", "gemma", "items": [(sample, clap result, gemma result)]}, biggest group first."""
    parts = [f"<!doctype html><meta charset=utf-8><title>Categories: CLAP and EmbeddingGemma 2</title>"
             f"<style>{STYLE}</style>", "<h1>How CLAP and EmbeddingGemma 2 categorise your library</h1>",
             f"<p>{escape(intro)}</p>", "<p class=muted>Click a name to play it, click again to stop. "
             "Percentages are each model's confidence in its pick.</p>",
             "<ul>", *[f"<li>{escape(line)}</li>" for line in agreement], "</ul>",
             "<h2>Most common differences</h2>", "<table><tr><th>CLAP said</th><th>EmbeddingGemma 2 said</th>"
             "<th>Sounds</th></tr>",
             *[f"<tr><td><a href='#g{i}'>{escape(c)}</a></td><td>{escape(g)}</td><td>{n}</td></tr>"
               for i, (c, g, n) in enumerate(changes)], "</table>",
             "<h2>How many sounds each model puts in each category</h2>",
             "<table><tr><th>Category</th><th>CLAP</th><th>EmbeddingGemma 2</th></tr>",
             *[f"<tr><td>{escape(name)}</td><td>{a}</td><td>{b}</td></tr>" for name, a, b in distribution], "</table>",
             f"<h2>Every sound categorised differently ({sum(len(g['items']) for g in groups)})</h2>"]
    for i, group in enumerate(groups):
        parts += [f'<h3 id="g{i}">CLAP: {escape(group["clap"])} → EmbeddingGemma 2: {escape(group["gemma"])} '
                  f'<small>{len(group["items"])} sound{"" if len(group["items"]) == 1 else "s"}</small></h3>',
                  "<table><tr><th>Sound</th><th>CLAP</th><th>EmbeddingGemma 2</th></tr>"]
        for sample, clap, gemma in group["items"]:
            parts.append(f"<tr><td>{_player(sample)}</td><td>{_verdict(clap)}</td><td>{_verdict(gemma)}</td></tr>")
        parts.append("</table>")
    parts.append(f"<script>{SCRIPT}</script>")
    return "\n".join(parts)

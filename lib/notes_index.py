"""Generate README.md and graph.md from note frontmatter and wiki-links."""

import re
import sys
from collections import defaultdict
from pathlib import Path


def parse_frontmatter(text: str) -> dict:
    """Extract YAML frontmatter fields from note text."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}

    fm = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" in line:
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip()

    # Parse specific fields
    result = {}
    result["title"] = fm.get("title", "").strip("\"'")
    result["created"] = fm.get("created", "").strip("\"'")
    result["updated"] = fm.get("updated", "").strip("\"'")
    result["type"] = fm.get("type", "").strip("\"'")

    # Parse list fields: [item1, item2]
    for field in ("tags", "related"):
        raw = fm.get(field, "")
        if raw.startswith("[") and raw.endswith("]"):
            items = [i.strip().strip("\"'") for i in raw[1:-1].split(",") if i.strip()]
            result[field] = items
        else:
            result[field] = []

    return result


def scan_wiki_links(text: str) -> list[str]:
    """Find all [[wiki-links]] in body text (after frontmatter)."""
    # Strip frontmatter
    parts = text.split("---", 2)
    body = parts[2] if len(parts) >= 3 else text

    # Matches [[slug]] and [[slug|display text]]
    return sorted(set(re.findall(r"\[\[([a-z0-9-]+)(?:\|[^\]]+)?\]\]", body)))


def main():
    notes_dir = Path(sys.argv[1])
    skip = {"README.md", "graph.md"}

    # Collect all note data
    notes = {}  # slug -> {title, tags, related, created, updated, links}
    tags_index = defaultdict(list)  # tag -> [slugs]
    backlinks = defaultdict(list)  # target_slug -> [source_slugs]
    unconverted = []  # filenames without frontmatter

    for f in sorted(notes_dir.glob("*.md")):
        if f.name in skip:
            continue

        slug = f.stem
        text = f.read_text()
        fm = parse_frontmatter(text)

        if not fm or not fm.get("title"):
            unconverted.append(f.name)
            continue

        links = scan_wiki_links(text)
        notes[slug] = {**fm, "links": links}

        for tag in fm.get("tags", []):
            tags_index[tag].append(slug)

        for link in links:
            backlinks[link].append(slug)

    # --- Generate README.md ---
    sorted_tags = sorted(tags_index.keys())
    sorted_slugs = sorted(notes.keys())

    readme_lines = [
        "# Shared Notes",
        "",
        "Auto-generated index. Do not edit manually — run `notes index` to rebuild.",
        "",
    ]

    # Tag cloud
    readme_lines.append("## Tags")
    readme_lines.append("")
    cloud = " ".join(f"`{t}` ({len(tags_index[t])})" for t in sorted_tags)
    readme_lines.append(cloud if cloud else "*No tags yet.*")
    readme_lines.append("")

    # By-tag index
    readme_lines.append("## Notes by Tag")
    readme_lines.append("")
    for tag in sorted_tags:
        readme_lines.append(f"### {tag}")
        readme_lines.append("")
        for slug in sorted(tags_index[tag]):
            n = notes[slug]
            title = n["title"]
            dates = []
            if n["created"]:
                dates.append(f"created {n['created']}")
            if n["updated"]:
                dates.append(f"updated {n['updated']}")
            date_str = f" ({', '.join(dates)})" if dates else ""
            readme_lines.append(f"- [{title}]({slug}.md){date_str}")
        readme_lines.append("")

    # All notes table
    readme_lines.append("## All Notes")
    readme_lines.append("")
    readme_lines.append("| Note | Tags | Updated |")
    readme_lines.append("|------|------|---------|")
    for slug in sorted_slugs:
        n = notes[slug]
        title = n["title"]
        tags = ", ".join(n.get("tags", []))
        updated = n.get("updated", "") or "\u2014"
        readme_lines.append(f"| [{title}]({slug}.md) | {tags} | {updated} |")
    readme_lines.append("")

    # Unconverted notes
    readme_lines.append("## Notes Without Frontmatter")
    readme_lines.append("")
    if unconverted:
        for fname in sorted(unconverted):
            readme_lines.append(f"- [{fname}]({fname})")
    else:
        readme_lines.append("*All notes have frontmatter.*")
    readme_lines.append("")

    (notes_dir / "README.md").write_text("\n".join(readme_lines))
    print(f"  README.md generated ({len(notes)} indexed notes, {len(sorted_tags)} tags)")

    # --- Generate graph.md ---
    graph_lines = [
        "# Link Graph",
        "",
        "Auto-generated backlink map. Do not edit manually — run `notes index` to rebuild.",
        "",
    ]

    # Outgoing links
    graph_lines.append("## Outgoing Links")
    graph_lines.append("")
    has_outgoing = False
    for slug in sorted_slugs:
        n = notes[slug]
        if n["links"]:
            link_str = ", ".join(f"[[{l}]]" for l in n["links"])
            graph_lines.append(f"- **{n['title']}** ({slug}) -> {link_str}")
            has_outgoing = True
    if not has_outgoing:
        graph_lines.append("*No outgoing links yet.*")
    graph_lines.append("")

    # Backlinks
    graph_lines.append("## Backlinks (Incoming)")
    graph_lines.append("")
    sorted_bl = sorted(backlinks.keys())
    if not sorted_bl:
        graph_lines.append("*No backlinks found yet.*")
    else:
        for target in sorted_bl:
            sources = backlinks[target]
            target_title = notes[target]["title"] if target in notes else target
            source_str = ", ".join(
                f"[[{s}]] ({notes[s]['title']})" if s in notes else f"[[{s}]]"
                for s in sorted(sources)
            )
            graph_lines.append(f"- **{target_title}** ({target}) <- {source_str}")
    graph_lines.append("")

    # Explicit relations
    graph_lines.append("## Explicit Relations (frontmatter)")
    graph_lines.append("")
    has_relations = False
    for slug in sorted_slugs:
        n = notes[slug]
        related = n.get("related", [])
        if related:
            rel_str = ", ".join(f"[[{r}]]" for r in related)
            graph_lines.append(f"- **{n['title']}** ({slug}) <-> {rel_str}")
            has_relations = True
    if not has_relations:
        graph_lines.append("*No explicit relations defined yet.*")
    graph_lines.append("")

    # Orphaned notes
    graph_lines.append("## Orphaned Notes (no links)")
    graph_lines.append("")
    has_orphans = False
    for slug in sorted_slugs:
        n = notes[slug]
        has_links = bool(n["links"])
        has_bl = slug in backlinks
        has_rel = bool(n.get("related", []))
        if not has_links and not has_bl and not has_rel:
            graph_lines.append(f"- [{n['title']}]({slug}.md)")
            has_orphans = True
    if not has_orphans:
        graph_lines.append("*All notes are connected.*")
    graph_lines.append("")

    (notes_dir / "graph.md").write_text("\n".join(graph_lines))
    bl_count = len(sorted_bl)
    print(f"  graph.md generated ({bl_count} notes with backlinks)")


if __name__ == "__main__":
    main()

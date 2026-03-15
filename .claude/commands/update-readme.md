Update the answers table in `README.md`.

Scan all markdown files in `answers/` (including subfolders). For each answer file:

1. Read the first line to extract the title (strip the `# ` prefix)
2. Build the relative path from the repo root

Rebuild the answers table in `README.md` between the `## Answers` heading and the next `##` heading. The table format is:

```
| # | Title | File |
|---|-------|------|
| 1 | Answer Title Here | [filename.md](answers/path/to/filename.md) |
```

Number rows sequentially. Sort alphabetically by filename. If answers are in subfolders, include the subfolder in the path.

After updating, report how many answers are indexed.

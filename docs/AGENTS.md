# AGENTS.md

Instructions for agents reading or editing the documentation in this folder.

## Where to start

1. Read `llms.txt` for the list of documents with one-line summaries.
2. Read `data/manifest.json` if you need structure: every document's metadata, dependencies and section anchors.
3. Open only the Markdown files you need. Each one declares what it `depends_on`, and lists the questions it `answers`.

## Files

| Path                 | Role                                                   | Edit by hand  |
| -------------------- | ------------------------------------------------------ | ------------- |
| `README.md`, `NN-*.md` | The documents. Source of truth.                      | Yes           |
| `examples/**`        | Files that code blocks include (optional)              | Yes           |
| `docs_ext.py`        | This project's extra checks and data files (optional)  | Yes           |
| `AGENTS.md`          | This file                                              | Yes           |
| `index.html`         | All documents as one static page for people            | No, generated |
| `llms.txt`           | Index for agents                                       | No, generated |
| `data/manifest.json` | Document metadata and section anchors                  | No, generated |
| `data/glossary.json` | Terms, from the table in `README.md`                   | No, generated |

## Front matter

Every document starts with YAML front matter.

| Key          | Type                                | Meaning                                                                                                              |
| ------------ | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `id`         | string                              | Stable identifier. Other documents refer to it. Never change it. `README.md` is `index`.                             |
| `title`      | string                              | Human title                                                                                                          |
| `order`      | integer                             | Position in the reading order. `README.md` is `0`; `NN-name.md` is `NN`.                                             |
| `summary`    | string                              | One sentence. Used in `llms.txt` and the manifest.                                                                   |
| `status`     | `design`, `provisional` or `stable` | `design`: proposed, unbuilt. `provisional`: a format expected to change. `stable`: agreed and not to change without review. |
| `updated`    | date, `YYYY-MM-DD`                  | Date of the last substantive change                                                                                  |
| `audience`   | list                                | Who the document is for                                                                                              |
| `depends_on` | list of ids                         | Documents to read first                                                                                              |
| `related`    | list of ids                         | Documents that cover adjacent topics                                                                                 |
| `defines`    | list                                | Terms this document defines or specifies in detail                                                                   |
| `answers`    | list                                | Questions this document answers. Use these to decide whether to open it.                                             |
| `data`       | path, optional                      | Generated data file derived from this document                                                                       |
| `examples`   | path, optional                      | Example files this document includes                                                                                 |

## Conventions

- **One term, one meaning.** Use the terms in `data/glossary.json` exactly. Do not introduce synonyms. A new term goes in the table in `README.md` first.
- **Identifiers are literal.** Text in backticks is an identifier, file name, field name or value, and is case-sensitive.
- **Headings are anchors.** Link to a section as `NN-name.md#heading-in-lower-case-with-hyphens`. Renaming a heading breaks links; the build reports them.
- **Tables are data.** Keep one fact per cell and keep column headers unchanged, because tables can be extracted into JSON.
- **Diagrams are plain text** inside fenced blocks, so they can be read without rendering.
- **Example code blocks are included, not written.** A block between `<!-- include: path -->` and `<!-- /include -->` is copied from that file by the build. Edit the file, not the block.
- **Open questions are open.** Do not resolve an undecided question by assumption; surface it.

## Changing the documents

1. Edit the Markdown or the included files.
2. Update `updated` in the front matter of each document you changed.
3. Run `docs-build` (or `uv run build.py` where a vendored copy lives in this folder). It needs pandoc.
4. Fix every error it reports. Do not commit with a failing build.

`docs-build --check` validates without writing anything.

## What the build checks

- Front matter has every required key, a valid `status`, and unique `id`s.
- `depends_on` and `related` refer to documents that exist.
- Every relative link resolves to a file, and every `#anchor` matches a heading.
- Included example blocks match their files.
- Anything this project adds in `docs_ext.py`.

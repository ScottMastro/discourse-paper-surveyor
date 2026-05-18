# paper-surveyor

A Discourse plugin that polls OpenAlex for new preprints and articles, filters
them by relevance with a Discourse AI agent, extracts and annotates figures
with a vision LLM, and posts AI-written summaries to configured categories.

Designed for narrow research communities (e.g. pangenomics) that want a
low-noise feed of relevant new literature without baby-sitting a script.

## What it does

Each scheduled run (hourly by default):

1. Queries the [OpenAlex](https://docs.openalex.org/) `/works` endpoint with
   a configurable keyword search, work-type filter, concept-id filter, and
   source-id filter. Cursor-paginated, polite-pool aware.
2. For each candidate, dedupes against the `paper_surveyor_seen_papers`
   table (by OpenAlex ID, by DOI, and by normalized title — the third gate
   catches Zenodo "version" / "all versions" duplicates).
3. Sends title + abstract to a **relevance agent** (cheap LLM, e.g. Claude
   Haiku). Anything below `paper_surveyor_relevance_threshold` is dropped.
4. For survivors: downloads the open-access PDF (where available), stores it
   server-side (never linked publicly), extracts every embedded image, and
   asks a vision LLM to classify each as `figure` / `table` / `boilerplate`
   plus generate a one-sentence description. Figures are persisted as
   `PaperSurveyor::Figure` rows with their Discourse `Upload`.
5. Extracts the full PDF text (References / Bibliography stripped to save
   tokens) and hands it — plus a manifest of every figure with description
   and upload URL — to a **summary agent** (e.g. Claude Opus). The model
   writes a 3-5 paragraph post in Discourse Markdown and embeds figures
   inline using standard `![](upload://…)` syntax, matching by *what the
   figure shows*, not by figure number.
6. Builds the topic body: citation block (italics preserved from OpenAlex
   HTML markup), quick-links row (publisher landing page, PDF, OpenAlex),
   summary with embedded figures, the original abstract in a `[details]`
   collapsible, and a footer.
7. Posts to the route's configured category.

A separate **backfill** path walks any date range through the same pipeline,
resumable via a persisted cursor on `PaperSurveyor::BackfillRun`.

## Pipeline shape

```
OpenAlex query
  → dedupe (openalex_id, doi, normalized title)
  → relevance agent     (cheap LLM)   ───┐
  → PDF fetch (OA-status gated)           │ skip if not relevant
  → image extract + vision annotate ──────┤
  → text extract (refs stripped)          │
  → summary agent (figures in prompt) ────┤
  → publish topic to route category  ◄────┘
```

## Routes

Two parallel routes share the keyword query but have their own
work-type filter and target category:

* **preprint** route — defaults to `type=preprint`
* **article** route — defaults to `type=article|review`

Either can be disabled by leaving its category empty. The model is
extensible — add an entry to `PaperSurveyor::Route.configured` for a third
route (e.g. `dataset`).

## Configuration

All settings live under `Admin → Site Settings → preprint surveyor`.
The plugin auto-seeds two `AiAgent` records on boot:

* **Paper Surveyor – Relevance** — scores 0.0-1.0 against the configured
  field of interest. Edit its system prompt in the AI admin UI.
* **Paper Surveyor – Summary** — writes the post body. Same idea.

The corresponding `paper_surveyor_*_agent_id` site settings are pointed at
the seeded agents automatically. An admin still has to assign each agent
a `default_llm_id` in the AI admin UI before it will run.

### Key settings

| Setting | What it does |
|---|---|
| `paper_surveyor_enabled` | Master switch. |
| `paper_surveyor_openalex_mailto` | Contact email for the OpenAlex polite pool. |
| `paper_surveyor_search_query` | Free-text search (title + abstract). Shared across routes. |
| `paper_surveyor_field_of_interest` | Plain-English description used in the relevance prompt. |
| `paper_surveyor_relevance_threshold` | Minimum score (0-1) to proceed. |
| `paper_surveyor_*_category_id` | Per-route target category. |
| `paper_surveyor_*_work_types` | Per-route OpenAlex work-type filter. |
| `paper_surveyor_store_pdfs` | Download PDFs for server-side processing (never linked from the post). |
| `paper_surveyor_extract_figures` | Run pdfimages + vision-LLM annotation. |
| `paper_surveyor_strip_references` | Drop References sections before LLM summarization. |
| `paper_surveyor_*_llm_model_id` / `*_agent_id` | Pick the LLM / agent for each step. |

## Admin UI

`/admin/plugins/paper-surveyor` lists every paper the pipeline has seen,
with status chips (Posted / Below threshold / Pending / Error / Filtered),
route filter, free-text search across title / DOI / OpenAlex ID, and
pagination.

## System dependencies

The plugin shells out to:

* `pdftotext` — text extraction (poppler-utils; ships with the
  Discourse base image)
* `pdfimages` — embedded-image extraction (same package)

No JVM, no Python, no extra services.

## Status

v0.1 — opinionated MVP for the pangytalk forum.

Known gaps / next-up:

* No tagging step yet (planned as a separate post-publish agent so it can be
  re-run independently against existing posts).
* bioRxiv content arrives via OpenAlex with weeks-to-months indexing lag,
  and bioRxiv's own PDFs sit behind Cloudflare bot protection — so bioRxiv
  papers tend to get abstract-only summaries until OpenAlex catches up.
  Research Square / medRxiv / arXiv / Preprints.org work cleanly.
* `paper_surveyor_poll_interval_minutes` is documentation-only — the
  scheduler is hardcoded to 1 hour. A real dynamic schedule needs a setting
  observer to re-register the Sidekiq schedule.

# Momentum — Product Requirements Document

**Version:** 1.0
**Date:** 2026-04-05
**Author:** Joaolucas
**Status:** Draft

---

## 1. Overview

### 1.1 Product Summary

Momentum is a native macOS desktop application that captures spoken thoughts during content consumption and converts them into structured, AI-analysed markdown notes — with zero interruption to the user's cognitive flow.

### 1.2 The Problem

When engaged in deep focus — reading, watching a documentary, studying, attending a lecture — two things happen simultaneously when a thought worth keeping appears:

1. **The idea is lost.** We tell ourselves we'll remember it. We don't.
2. **The flow state is broken.** Reaching for a pen, opening an app, deciding where to save — each micro-decision is a context switch. Once broken, the chain of thought that produced the idea is extremely difficult to re-enter.

Existing solutions (voice memos, note apps, paper) solve the capture problem but not the friction problem. They still require the user to switch context, make decisions, and manage the output.

### 1.3 The Solution

A single button (or keyboard shortcut) starts a recording. The user speaks their thought and returns to what they were doing. In the background, Momentum transcribes the audio, runs AI analysis, and writes a structured markdown file — without the user ever leaving their flow state.

### 1.4 Product Philosophy

> Momentum is not a note-taking app. It is a flow state protection tool. The measure of its success is how rarely the user thinks about it — and how often they find a thought they would have lost.

---

## 2. Goals & Non-Goals

### 2.1 V1 Goals

- Eliminate all friction between having a thought and capturing it
- Produce concise, scannable AI analysis (readable in under 60 seconds)
- Surface logical gaps in captured thoughts before the user acts on them
- Connect new captures to relevant past ones automatically
- Work offline (capture) and process when connectivity is restored
- Store all data locally in portable markdown files — no lock-in

### 2.2 Non-Goals (V1)

- Mobile or away-from-screen capture
- A browsing/reading UI for notes
- Text-based capture (reintroduces typing friction)
- Daily digests or aggregated views
- Third-party integrations (Notion, Obsidian, etc.)
- Local AI model processing

---

## 3. Users

### 3.1 Primary User

**The knowledge synthesizer** — someone who consumes large volumes of content (books, papers, documentaries, lectures, podcasts) and needs to convert external input into original personal thought. They are not trying to transcribe what someone else said — they want to record what *they thought* in response.

Characteristics:
- Heavy content consumer across multiple domains
- Values deep focus and dislikes interruptions
- Has lost ideas to the friction of note-taking before
- Comfortable with markdown and file-based workflows
- Technical enough to install a desktop app and configure an API key

### 3.2 V1 User

The builder himself. V1 success criteria: daily use, zero lost thoughts, no desire to go back to the previous workflow.

---

## 4. Use Cases

### 4.1 Core Use Cases

| Trigger | Description |
|---|---|
| **Reading** | A thought arises while reading a book or article. User hits shortcut, speaks the thought, returns to reading. |
| **Watching** | A documentary or lecture sparks a connection. User captures it without pausing playback. |
| **Studying** | During a study session, user externalises a developing idea chain before it collapses. |
| **Rubber Duck** | User is stuck on a problem. Speaks it aloud. AI stress-tests the reasoning and surfaces what's missing. |
| **Brain Dump** | Start of day. User speaks everything occupying working memory. AI finds contradictions and surfaces what actually needs attention. |

### 4.2 Out of Scope Use Cases (V1)

- Meeting transcription
- Interview recording
- Collaborative note-taking
- Long-form dictation

---

## 5. Features

### 5.1 Capture

| Feature | Description | Priority |
|---|---|---|
| Floating record button | Always-visible minimal UI — one button, start/stop | P0 |
| Global keyboard shortcut | Configurable shortcut that works regardless of focused app | P0 |
| Local audio storage | Recording saved to disk immediately on capture start | P0 |
| Offline capture queue | Captures made without internet are queued and processed when connected | P0 |
| Passive context capture | On record start, silently captures active window title + browser URL | P1 |

### 5.2 Processing Pipeline

| Feature | Description | Priority |
|---|---|---|
| Whisper transcription | Full verbatim transcript via OpenAI Whisper API | P0 |
| AI analysis | Structured analysis via GPT-4 (or configured model) | P0 |
| Plot hole detection | Default lens — checks for logical gaps, false assumptions, broken reasoning chains | P0 |
| Configurable lens prompt | User can replace or extend the default analysis prompt | P1 |
| AI domain tagging | 1-3 domain tags generated per capture, stored in frontmatter | P1 |
| Cross-session connections | AI surfaces links to related past captures inside each new note | P1 |
| Analysis brevity constraint | Hard token budget enforced in prompt — analysis scannable in <60 seconds | P0 |

### 5.3 Output

| Feature | Description | Priority |
|---|---|---|
| Markdown file per capture | One `.md` file per recording, saved to user-configured directory | P0 |
| Timestamp filename | `YYYY-MM-DDTHH-mm-ss.md` — no manual naming | P0 |
| Fixed two-section structure | `## Raw Transcription` + `## Analysis` always present | P0 |
| YAML frontmatter | timestamp, tags, source context written to frontmatter | P1 |
| Local capture index | `index.json` maintained per capture — enables connections lookup | P1 |

### 5.4 Configuration

| Feature | Description | Priority |
|---|---|---|
| API key management | User provides their own OpenAI (or other) API key | P0 |
| Model selection | User can swap AI model provider via config | P1 |
| Output directory | User sets where `.md` files are saved | P0 |
| Shortcut binding | User configures global keyboard shortcut | P0 |
| Lens prompt | User can customise the default analysis prompt | P1 |

### 5.5 Onboarding

| Feature | Description | Priority |
|---|---|---|
| Zero-config free tier | First N captures work without API key (built-in quota) | P2 |
| BYOK beyond quota | Users who exceed free tier provide their own API key | P2 |

---

## 6. MD File Specification

### 6.1 Filename

```
YYYY-MM-DDTHH-mm-ss.md
```

Example: `2026-04-05T14-32-00.md`

### 6.2 Full Structure

```markdown
---
timestamp: 2026-04-05T14:32:00
tags: [philosophy, product-thinking]
source_context:
  window_title: "Thinking, Fast and Slow — Chapter 12"
  browser_url: "https://example.com/article"
---

## Raw Transcription

[Verbatim audio transcript — no edits, no filtering]

## Analysis

### Plot Holes
- [Logical gap or false assumption #1]
- [Logical gap or false assumption #2]

### Summary
[2-3 sentences capturing the core of the thought]

### Key Points
- [Point 1]
- [Point 2]
- [Point 3]

### Dig Further
- [AI-suggested research direction based on configured lens]
- [Second direction]

### Connections
- [[2026-03-18T09-12-00]] — related thought on behaviour change
- [[2026-03-29T16-44-00]] — overlapping reasoning pattern
```

### 6.3 Analysis Constraints

The AI prompt must enforce:
- **Plot Holes:** maximum 3 items
- **Summary:** maximum 3 sentences
- **Key Points:** 3–5 bullets
- **Dig Further:** 2–3 items
- **Connections:** 2–3 links
- **Total analysis word count:** ≤ 200 words

---

## 7. Software Architecture

### 7.1 Stack

| Layer | Technology |
|---|---|
| Application shell | Electron |
| Language | TypeScript |
| Target OS | macOS (v1) |
| Transcription | OpenAI Whisper API |
| Analysis | OpenAI Chat API (GPT-4o) |
| Config persistence | `electron-store` |
| Audio recording | `node-record-lpcm16` |
| Active window context | `active-win` |

### 7.2 Module Map

```
src/
├── main.ts              # App entry, lifecycle, shortcut registration
├── tray.ts              # System tray icon + floating button window
├── recorder.ts          # Audio capture, temp file management, context grab
├── queue.ts             # Offline queue, connectivity polling, retry logic
├── pipeline.ts          # Transcription → analysis → write orchestration
├── providers/
│   ├── interface.ts     # AIProvider interface (swap models freely)
│   └── openai.ts        # OpenAI implementation (Whisper + GPT-4)
├── writer.ts            # MD file builder + frontmatter serialiser
├── index.ts             # Capture index (index.json) read/write
└── config.ts            # electron-store wrapper, typed config schema
```

### 7.3 Processing Flow

```
User triggers capture
       │
       ▼
Recorder starts → saves audio to temp file
Passive context grabbed (window title, URL)
       │
       ▼
User stops recording
       │
       ▼
Queue Manager receives { audioPath, context, timestamp }
Queue item persisted to queue.json
       │
       ▼ (when online)
Pipeline:
  1. POST audio → Whisper API → raw transcript
  2. Load last 20 entries from index.json (summaries + tags)
  3. POST transcript + index context + lens prompt → GPT-4 → structured JSON
  4. Parse JSON → validate structure
       │
       ▼
Writer:
  - Build YAML frontmatter
  - Compose MD sections
  - Write to output directory
       │
       ▼
Index Manager:
  - Append { filename, tags, summary, timestamp } to index.json
       │
       ▼
Tray icon returns to idle state
```

### 7.4 AI Provider Interface

```typescript
interface AIProvider {
  transcribe(audioPath: string): Promise<string>
  analyse(transcript: string, context: AnalysisContext): Promise<AnalysisResult>
}

interface AnalysisResult {
  plotHoles: string[]
  summary: string
  keyPoints: string[]
  digFurther: string[]
  connections: Connection[]
  tags: string[]
}
```

Swapping models = implementing this interface and updating config. No other changes.

### 7.5 Queue Schema

```typescript
interface QueueItem {
  id: string
  audioPath: string
  context: {
    windowTitle?: string
    browserUrl?: string
  }
  timestamp: string
  attempts: number
  status: 'pending' | 'processing' | 'failed'
}
```

---

## 8. Analysis Prompt Design

The analysis prompt is the hardest engineering problem in the product. Quality here is the north star metric.

### 8.1 Default Prompt Structure

```
You are analysing a thought captured during a focus session.

TRANSCRIPT:
{transcript}

PAST CAPTURES (for connections):
{index_context}

Your job:
1. PLOT HOLES — find logical gaps, false assumptions, or broken reasoning chains in the thought. Be direct. Maximum 3.
2. SUMMARY — distil the core idea in 2-3 sentences. No padding.
3. KEY POINTS — 3-5 bullets of the most important elements.
4. DIG FURTHER — 2-3 directions worth exploring based on what was captured. 
5. CONNECTIONS — 2-3 links to past captures that relate. Format: filename — one-line reason.
6. TAGS — 1-3 domain tags (e.g. philosophy, neuroscience, product-thinking).

STRICT CONSTRAINT: Total analysis must be under 200 words. Favour precision over completeness.

{lens_prompt}

Respond in JSON matching this exact schema: { plotHoles, summary, keyPoints, digFurther, connections, tags }
```

### 8.2 Default Lens Prompt

```
Apply critical thinking: treat the captured thought as a hypothesis. 
Where does the reasoning assume something that might not be true? 
What step in the chain is doing more work than it should?
```

### 8.3 Lens Customisation

The `{lens_prompt}` variable is replaced at runtime with whatever the user has configured. Empty by default beyond the default lens above. Examples a user might set:

- `"Focus on connections to existing systems thinking principles."`
- `"What would a strong counter-argument look like?"`
- `"Identify the most actionable implication of this thought."`

---

## 9. V1 Build Order

| Phase | Deliverable |
|---|---|
| 1 | Electron scaffold + system tray + hide from dock |
| 2 | Global shortcut + floating button UI |
| 3 | Audio capture → temp `.wav` file |
| 4 | Whisper transcription (hardcoded key) |
| 5 | GPT-4 analysis prompt → structured JSON output |
| 6 | MD file writer + output directory |
| 7 | Index manager (`index.json`) + connections in analysis |
| 8 | Offline queue + connectivity polling |
| 9 | Passive context capture (window title, browser URL) |
| 10 | Config UI (API key, output dir, shortcut, lens prompt) |
| 11 | Model-agnostic provider abstraction |
| 12 | Zero-config free tier (optional, post-core) |

---

## 10. Success Metrics

| Metric | Target |
|---|---|
| Daily active use | Used every day the builder consumes content |
| Captures lost to friction | Zero — every capture attempt completes |
| Analysis read time | ≤ 60 seconds per note |
| Plot holes surfaced that changed thinking | ≥ 1 per week |
| Connections surfaced that were non-obvious | ≥ 1 per week |
| Time from stop-recording to MD file written | < 30 seconds (when online) |

---

## 11. Post-V1 Backlog

| Feature | Notes |
|---|---|
| Integrations (Obsidian, Notion) | MD files as the stable base layer |
| Mobile capture | Away-from-screen use case |
| In-recording segment markers | For long multi-topic captures |
| Open questions backlog (`questions.md`) | Running list of intellectual open threads |
| Configurable analysis section order | After core is stable |
| Coherence scoring | Flag low-signal captures before processing |
| Local AI model support | When feasible — Whisper local + local LLM |

---

## 12. Open Questions

| Question | Status |
|---|---|
| Free tier quota size (how many captures before BYOK?) | To decide |
| Connectivity check mechanism (DNS lookup interval?) | To decide |
| Index context window size (last 20 captures? all?) | To decide — balance cost vs. connection quality |
| macOS permissions flow (mic access, accessibility for browser URL) | To prototype |
| Audio format (WAV vs MP3 for Whisper API cost/quality tradeoff) | To decide |

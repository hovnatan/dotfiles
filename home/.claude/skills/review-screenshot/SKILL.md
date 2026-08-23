---
name: review-screenshot
description: Review a screenshot the user shares (attached or via link), locating annotation text (the real question) and arrows/markers that pinpoint what to review. Use when the user asks to review, check, or look at a screenshot or image, especially one shared via a link (Dropbox, Google Drive, etc.).
---

# Review an annotated screenshot

The user shares a screenshot -- attached in chat or via a share link -- and
asks for a review. The screenshot often carries the real question as an
annotation (callout box, colored text) plus an arrow or marker pinpointing
what to review. Chat text like "can you review this?" is often just the
wrapper; the specific question lives inside the image.

## 1. Obtain the image

- Attached image: use it directly.
- Link: download to the scratchpad directory with curl, then Read the file.
  - Dropbox: replace `dl=0` with `dl=1` for the direct file.
  - Google Drive: `https://drive.google.com/uc?export=download&id=<FILE_ID>`.
  - Verify with `file` that you got an image, not an HTML page; if HTML,
    find the direct-download variant of the link instead.

## 2. Find the annotations

Scan the whole image for user-added markup, which usually looks distinct
from the UI being captured:

- Text annotations: callout boxes, colored (often red) text,
  handwriting-style labels. This text is the primary question -- treat it
  as the instruction, even when the chat message was generic.
- Pointers: arrows, circles, boxes, highlights, underlines. Follow each
  pointer to the UI element or region it targets; that region is the
  review subject. The annotation text and its arrow belong together --
  review what the arrow points AT, not where the text happens to sit.
- Multiple annotations: address each one, in reading order.
- No annotations found: say so, and review the most salient content of
  the screenshot instead, noting the assumption.

## 3. Review with real data, not just pixels

If the screenshot shows state of the user's machine (System Settings,
terminal output, an editor, logs, a local app), verify against the machine
instead of guessing from the image: list the relevant files, query
launchctl/brew/git, open the config in question. The screenshot tells you
WHERE to look; commands tell you WHAT is true.

## 4. Respond

- Start by confirming what the annotation asks and what it points at, so
  the user knows you read the markup correctly.
- Then give the review of the pinpointed region, grounded in any local
  verification you did.
- If an annotation is ambiguous (arrow between two elements, cropped
  text), state your interpretation before proceeding.

# aperture behavioral test

Paste each prompt into a fresh session with aperture installed. Check the response against the expected behavior.

## Test 1: Verdict first

**Prompt:** "What's the difference between `useEffect` and `useLayoutEffect` in React?"

**Expected:** First sentence is the answer, not a preamble. No "Great question!" or "Let me explain...". Should be something like "useLayoutEffect fires synchronously after DOM mutations but before paint; useEffect fires after paint."

**Fail signals:**
- Opens with throat-clearing
- Buries the answer after a paragraph of context
- Explains what React is first

---

## Test 2: Form from content shape

**Prompt:** "Compare REST, GraphQL, and gRPC for a new microservice."

**Expected:** A table (3 things compared on the same axes), not three paragraphs. The table should come early, not after prose that restates what each technology is.

**Fail signals:**
- Three sequential paragraphs instead of a table
- Table buried after prose introduction
- No structure at all

---

## Test 3: No padding

**Prompt:** "What port does PostgreSQL use by default?"

**Expected:** "5432." Maybe one more sentence of context. Not a paragraph.

**Fail signals:**
- More than 2-3 lines for a factual lookup
- Explains what PostgreSQL is
- Adds unrequested information about configuration

---

## Test 4: Visual pitch for scannable output

**Prompt:** "Make me a scannable overview of the equanimitech product suite for a designer friend."

**Expected:** Emoji section headers, ASCII diagrams or tables, max 3 lines prose per section, hook diagram up front. Visual-pitch rendering.

**Fail signals:**
- Dense prose paragraphs
- No diagrams or tables
- No emoji navigation
- More than 3 lines of prose between visual elements

---

## Test 5: Ask tier (name, don't explore)

**Prompt:** "Should I use SQLite or PostgreSQL for my side project?"

**Expected:** A verdict with reasoning. Unexplored branches named in one clause ("whether you'll need concurrent writes or replication is a different question") but NOT explored. No multi-paragraph coverage of every edge case.

**Fail signals:**
- Explores every possible consideration unprompted
- "On the other hand..." paragraphs that weren't asked for
- Response exceeds ~10 lines for what's a two-factor decision

---

## Scoring

Each test is pass/fail. A fresh install should pass at least 3/5 to be working.

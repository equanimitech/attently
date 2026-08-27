# attently behavioral test

Paste each prompt into a fresh session with attently installed. Check the response against the expected behavior.

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

## Test 3: Wiki trigger (3+ sources)

**Prompt:** "I have a Next.js app with Prisma and Tailwind. The build is failing with a PostCSS error after upgrading to Tailwind v4. Here's the error: `Error: Cannot find module 'tailwindcss/plugin'`. Fix it."

**Expected:** Short answer in the reply (the fix). A wiki page written to `.claude/attently/` with the investigation details (what was read, what was tried, what was ruled out), linked by absolute path.

**Fail signals:**
- No wiki page despite reading 3+ files
- Wiki page is just a longer version of the reply
- No absolute path link in the reply

---

## Test 4: No padding

**Prompt:** "What port does PostgreSQL use by default?"

**Expected:** "5432." Maybe one more sentence of context. Not a paragraph.

**Fail signals:**
- More than 2-3 lines for a factual lookup
- Explains what PostgreSQL is
- Adds unrequested information about configuration

---

## Test 5: Visual pitch for scannable output

**Prompt:** "Make me a scannable overview of the equanimitech product suite for a designer friend."

**Expected:** Emoji section headers, ASCII diagrams or tables, max 3 lines prose per section, hook diagram up front. Visual-pitch rendering.

**Fail signals:**
- Dense prose paragraphs
- No diagrams or tables
- No emoji navigation
- More than 3 lines of prose between visual elements

---

## Test 6: Ask tier (name, don't explore)

**Prompt:** "Should I use SQLite or PostgreSQL for my side project?"

**Expected:** A verdict with reasoning. Unexplored branches named in one clause ("whether you'll need concurrent writes or replication is a different question") but NOT explored. No multi-paragraph coverage of every edge case.

**Fail signals:**
- Explores every possible consideration unprompted
- "On the other hand..." paragraphs that weren't asked for
- Response exceeds ~10 lines for what's a two-factor decision

---

## Scoring

Each test is pass/fail. A fresh install should pass at least 4/6 to be working. The wiki trigger (test 3) is the hardest -- it requires a real investigation context, so it may need a real codebase to fire properly.

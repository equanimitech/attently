#!/usr/bin/env node
/**
 * attently — adaptive granularity for AI assistants.
 *
 * Emits a depth contract on the turn boundary. That is the whole program.
 *
 * It decides nothing, blocks nothing, and stores nothing: no state file, no log,
 * no reading of your machine. The contract is a constant, so there is nothing to
 * observe you with. Depth is rationed by what an answer costs you to read, and the
 * only thing that raises it is you asking.
 *
 * Why a hook and not a skill: a skill governs when it is remembered. A turn-boundary
 * hook governs because it arrives. The posture has to be the default, not the thing
 * you invoke once you have already been handed four paragraphs.
 */

/** The full contract — rendered once, at session start. */
const CONTRACT = [
  "[attently] ▤ depth contract — gross to subtle. Sort by what it costs the reader, not by length.",
  "  glance (0s)    the verdict, in the reply. This is the default. Fit the ask; when in doubt, shorter.",
  "  click  (~2s)   the working — what was read, weighed, and rejected — in a file, linked by ABSOLUTE path.",
  "  ask    (a turn) the branch not taken. It does not exist yet; do not pre-empt it.",
  "These are different content, not one answer at three lengths: verdict, evidence, unexplored.",
  "Write a file only when real work would otherwise be discarded. Never pad a reply to fill a rung.",
].join("\n");

/** The per-turn reminder — deliberately ~20 tokens. The contract binds by arriving, not by arguing. */
const NUDGE = "[attently] ▤ glance first — verdict in the reply, working on disk, links not paragraphs.";

/** Hook output is plain stdout; anything written becomes context. Always exit 0 — attently never blocks a turn. */
const emit = (text) => { if (text) process.stdout.write(`${text}\n`); process.exit(0); };

/** Hooks are handed JSON on stdin. attently reads nothing from it, but drains it so the writer never sees EPIPE. */
async function drain() {
  try { for await (const _ of process.stdin) { /* discarded by design */ } } catch { /* fail-open */ }
}

async function main() {
  const [, , cmd, sub] = process.argv;
  if (cmd !== "hook") {
    console.log("attently — adaptive granularity for AI assistants.\nusage: attently hook <session-start|user-submit>");
    process.exit(0);
  }
  await drain();
  if (sub === "session-start") return emit(CONTRACT);
  if (sub === "user-submit") return emit(NUDGE);
  return emit("");
}

main().catch(() => process.exit(0));

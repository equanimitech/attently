---
$attestation:
  $type: tech.equanimi.secretariat.stamp
  signer: did:key:z6MkjB8PQaN1vuUzdtnJsxyXR2f8d3tckGHkUYZMDytQsfak
  act: attest
  docHash: sha256:aeb5c5634601bbe1b78dfd3c8d6e7246d9dda255b1ff23f8f9c08fae0995ea73
  docFilename: signet-pitch-yanik.md
  stampedAt: 2026-05-27T19:53:52.724326Z
  signature: ed25519:keBVs9vYpv/gIXyIYki61ghbRmSYtOneboKMBqZICd+dWRQhzgBfEnHlArYr+9zJDXs7TtUu+eMVcy7Rv8c6Dw==
---
# Signet

### *an attestation primitive for the AI age*

*Rafa → Yanik · 2026-05-27*

***

## 🪧 The bet, in one image

```
   agents act  ───────►  humans attest  ───────►  docs travel
       ⚙️                    👆🪪                      📄✅
   (volume up 100×)     (Touch ID stamp)        (seal rides inside)
```

***

## 😵‍💫 The PM nightmare you already live in

> *A Notion page lands in your inbox.*
>
> — *Did a human write it?*
> — *Did a human read it before it shipped?*
> — *Did anyone actually agree to the decision it claims was made?*
>
> **You don't know. The doc looks the same either way.**

***

## 📊 Before / After

| <br />             | **Today**                | **With Signet**               |
| ------------------ | ------------------------ | ----------------------------- |
| Approval           | Slack 👍                 | Cryptographic seal on the doc |
| Travels with file? | ❌ vanishes on copy       | ✅ embedded in frontmatter     |
| Verify offline?    | ❌ "trust me bro"         | ✅ anyone, no server           |
| Who stamped it?    | 🤷                       | 🪪 named human DID            |
| Which version?     | "the latest one I think" | 🔒 exact bytes, hashed        |

***

## 🧱 Where it sits

```
      cosign  →  artifacts        (container images)
      age     →  encryption       (file privacy)
      JWT     →  sessions         (auth tokens)
   ─────────────────────────────────────────────────
   ★  SIGNET  →  attestation      (human ↔ document)
```

Same family. New layer. **Identity + intent, embedded in the doc.**

***

## ⚡ The product, in 3 lines

```bash
cargo install signet signet-mcp
signet init
claude mcp add signet
```

> Now your agent can draft.
> You can stamp.
> The doc carries the proof — forever, anywhere it travels.

***

## 🧠 Why now (3 forces colliding)

```
  📝 agentic output ────┐
                        │
  🪪 DIDs mature ───────┼──►  the primitive is finally cheap
                        │
  👆 biometrics ────────┘
     everywhere
```

Every laptop has a fingerprint sensor. Every agent has access to your docs. The missing piece is the **stamp**.

***

## 🎯 The PM job-to-be-done

```
    your AI drafts ────►  PRD · launch comms · postmortem
                           │
                           ▼
                   [ ship it? 👆 ]
                           │
                           ▼
                  ┌─────────────────┐
                  │  ✅ stamped doc  │  ← travels w/ truth
                  └─────────────────┘
```

The artifact **is** the receipt.

***

## ❌ What Signet is *not*

* ~~DRM~~

* ~~Approval workflow~~

* ~~CMS~~

* ~~"signing app"~~ *(too small — names the verb, not the layer)*

***

## 🌅 The 5-year bet

> **Every artifact your team ships will be co-authored with agents.**
>
> The ones that carry a verifiable human stamp will be trusted.
>
> The ones that don't, won't.

***

## 📍 Status

**Pre-v0.1.** Spec + Rust reference impl in progress. MIT.

Three crates: `signet` (CLI) · `signet-mcp` (agent surface) · `signet-core` (protocol).

Narrative cover: Marcelo Ballestiero's *Autonomous Enterprise* — bounded-autonomy agent contracts replacing dashboard-driven management. Signet = the identity layer underneath it.

***

*👀 pushback welcome — sharpening before it goes wider.*

// attently as a mod: the depth contract as a system-prompt section, a turn band with the reader's
// recurring replies, read feedback on wiki pages, and the ring as a pane (/ring). Needs a Claude
// Code build that loads hooks modules (mods); without one the shell hooks in hooks.json run
// alone, exactly as in 0.7.0.
import { atom, read, update } from 'claude-code'
import type { ClassicResultOf, EngineInterface, Register } from 'claude-code'

import type { Card, Page } from '../types'

const turn = atom({ plugin: 'attently', key: 'turn' } as const, null, { shape: 'turn-1' })
const isTyping = atom({ plugin: 'attently', key: 'isTyping' } as const, false)
const pages = atom({ plugin: 'attently', key: 'pages' } as const, [], { shape: 'pages-1' })
const shown = atom({ plugin: 'attently', key: 'shown' } as const, null, { shape: 'shown-1' })
const cards = atom({ plugin: 'attently', key: 'cards' } as const, [], { shape: 'cards-1' })

const RING = 'attently-ring'
const PAGE = 'attently-page'
const STRETCH = 'A stretch grows the claim; a page shows the work.'
const CLOSE_UP = "Please run /close-up to land this session's progress."

// The marker: the reply's last line, markdown chrome stripped, when it opens with ✓ or ✋ (✔ ✅
// and the legacy ⏸ normalised, as ring_marker does); '' for anything else.
export const markerOf = (answer: string) => {
  const last = (answer.trimEnd().split('\n').at(-1) ?? '')
    .replace(/[`*️]|^\s*(>\s*)*([-+]\s+|#+\s+|\d+[.)]\s+)?/gu, '')
    .trim().replace(/^[✔✅]/u, '✓').replace(/^⏸/u, '✋')
  return /^[✓✋]/u.test(last) ? last : ''
}

// The wiki pages a reply links (.claude/attently/<page>.md), each once.
export const pagesOf = (answer: string) =>
  [...new Set(answer.match(/[^\s()<>[\]`'"]*\.claude\/attently\/[^\s()<>[\]`'"/]+\.md/g) ?? [])]

// What the model reads beside the reader's next typed prompt.
export const readLines = (list: Page[]) =>
  list.map(p => `attently: the reader ${p.isOpened ? 'opened' : 'did not open'} ${p.name}`).join('\n')

// The contract as the shell hooks read it, once per load. A read that fails fails the hooks
// that need it, which are then skipped: the shell contract stands, as in 0.7.0.
let contract: Promise<string[]> | undefined
const texts = ($: EngineInterface) =>
  (contract ??= Promise.all(['session-start.md', 'turn.md'].map(f => $.fs.read(`${$.plugin.root}/contract/${f}`))))

// The shell hooks run beneath every module, so their context arrives here: take the contract
// out of it (the section carries it now) and keep the handoff lines they add beside it.
const standDown = async <R extends ClassicResultOf['classic.SessionStart' | 'classic.UserPromptSubmit']>($: EngineInterface, r: R) => {
  if (!r.additionalContext) return r
  const own = (await texts($)).map(t => t.trim())
  const additionalContext = r.additionalContext
    .map(c => own.reduce((s, t) => s.replace(t, ''), c))
    .map((s, i) => (s === r.additionalContext?.[i] ? s : s.trim()))
    .filter(Boolean)
  return { ...r, additionalContext }
}

const ringDir = async ($: EngineInterface) =>
  `${(await $.env.get('ATTENTLY_HOME')) ?? `${await $.env.get('HOME')}/.claude/attently`}/ring/sessions`

// Read, merge, write, as ring.sh merges the same card (ring_json_merge), so its fields stay.
// ponytail: no lock; a write racing ring.sh's can drop a field until the next turn rewrites it.
const mergeCard = async ($: EngineInterface, fields: Partial<Card>) => {
  const session = await $.session.id()
  const path = `${await ringDir($)}/${session}.json`
  const old = await $.fs.read(path).then(JSON.parse).catch(() => ({}))
  const ts = Math.floor((await $.clock.now()) / 1000)
  await $.fs.write(path, `${JSON.stringify({ ...old, session, cwd: await $.session.cwd(), ...fields, ts })}\n`)
}

const refresh = async ($: EngineInterface) => {
  const dir = await ringDir($)
  const files = (await $.fs.list(dir).catch(() => [])).filter(f => f.name.endsWith('.json'))
  const list = await Promise.all(files.map(f => $.fs.read(`${dir}/${f.name}`).then(JSON.parse).catch(() => undefined)))
  await update($, cards, () => list.filter((c): c is Card => typeof c?.session === 'string'))
}

const ago = (s: number) =>
  s < 60 ? `${Math.max(0, s)}s` : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`

export const register: Register = (on, options) => {
  const replies = String(options.replies ?? '').split('·').map(r => r.trim()).filter(Boolean)
  let polling: { cancel: () => void } | undefined

  // Contract: one section, after the engine's own, kept across /compact.
  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    const [text = ''] = await texts($)
    const section = text.trim().replace('\n## The ask', `\n${STRETCH}\n\n## The ask`)
    return { sections: [...r.sections, { id: 'attently:contract', text: section, scope: 'session' }] }
  })
  on('classic.SessionStart', async ($, e, next) => standDown($, await next(e)))
  on('classic.UserPromptSubmit', async ($, e, next) => standDown($, await next(e)))

  // The band hides while the prompt holds text.
  on('prompt.change', async ($, e, next) => {
    const typing = e.text.trim() !== ''
    if ((await read($, isTyping)) !== typing) await update($, isTyping, () => typing)
    return next(e)
  })

  // Read feedback rides the reader's next typed prompt, never a press or a command.
  on('prompt.submit', async ($, e, next) => {
    const isTyped = (e.origin.kind === 'composer' || e.origin.kind === 'bridge') && !e.command
    const list = isTyped ? await read($, pages) : []
    if (!list.length) return next(e)
    await update($, pages, () => [])
    return next({ ...e, context: [...(e.context ?? []), readLines(list)] })
  })

  on('turn.start', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId === undefined) {
      await update($, turn, () => null)
      await mergeCard($, { state: 'working' })
    }
    return r
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId !== undefined) return r
    const marker = markerOf(e.answer)
    await update($, turn, () => marker)
    const linked = pagesOf(e.answer)
    await update($, pages, old => [
      ...old,
      ...linked.filter(path => !old.some(p => p.path === path))
        .map(path => ({ name: path.split('/').at(-1)?.replace(/\.md$/, '') ?? path, path, isOpened: false })),
    ])
    await mergeCard($, { state: marker.startsWith('✋') ? 'waiting' : 'done', marker })
    return r
  })

  // Inside cmux ring.sh releases the card (and needs it to); outside, nothing else would.
  on('session.end', async ($, e, next) => {
    const r = await next(e)
    if (!(await $.env.get('CMUX_WORKSPACE_ID'))) await $.process.run(['rm', '-f', `${await ringDir($)}/${e.sessionId}.json`])
    return r
  })

  // Turn band: idle after a main-loop turn, the marker glyph, then one press per reply. It sits
  // under whatever else draws there (oliba's wait band draws while working).
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)
    const marker = await read($, turn)
    if (marker === null || e.props.isWorking || e.props.hasSurvey || (await read($, isTyping))) return below
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = await read($, pages)
    const reply = async (text: string) => {
      await update($, turn, () => null)
      await $.prompt.submit({ text, asUser: true })
    }
    const open = async (p: Page) => {
      const text = await $.fs.read(p.path).catch(() => `${p.path} is gone.`)
      await update($, pages, now => now.map(o => (o.path === p.path ? { ...o, isOpened: true } : o)))
      await update($, shown, () => ({ name: p.name, text }))
      await $.ui.open({ id: PAGE, title: p.name, focus: true, closeOnEscape: true })
    }
    return (
      <Box flexDirection="column" width={e.props.bodyColumns}>
        {below}
        <Box gap={1} flexWrap="wrap">
          <Text>{marker.slice(0, 1) || '·'}</Text>
          {replies.map((text, i) => <Button key={`reply-${i}`} label={text} onPress={() => reply(text)} />)}
          {list.map(p => <Button key={`open-${p.path}`} label={`Open ${p.name}`} onPress={() => open(p)} />)}
        </Box>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PAGE }, async ($, e) => {
    const { Markdown, Text } = $.ui.resolve(e)
    const page = await read($, shown)
    return page ? <Markdown text={page.text} /> : <Text dimColor>No page open.</Text>
  })

  // Ring pane: one row per card, polled every 5 s only while open.
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'ring', description: 'Every Claude session at a glance: state, age, repo' })
    return next(e)
  })
  on('command.run', { command: 'ring' }, async $ => {
    await refresh($)
    polling?.cancel()
    polling = $.clock.every(5000, () => void refresh($))
    await $.ui.open({ id: RING, title: 'Ring', focus: true })
    return { text: 'Ring opened.' }
  })
  on('ui.close', { id: RING }, ($, e, next) => {
    polling?.cancel()
    polling = undefined
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: RING }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = await read($, cards)
    const self = await $.session.id()
    const now = Math.floor((await $.clock.now()) / 1000)
    const closeUp = async (session: string) => {
      const sent = await $.session.send({ to: { sessionId: session }, text: CLOSE_UP })
      $.ui.toast(sent.isDelivered ? 'attently: close-up sent' : `attently: not sent, ${sent.reason}`)
    }
    return (
      <Box flexDirection="column" width={e.props.bodyColumns}>
        <Button key="midday" label="Midday" onPress={() => $.command.run({ command: 'zenborg:midday', args: '' })} />
        {list.length === 0 && <Text dimColor>No live sessions.</Text>}
        {list.map(c => (
          <Box key={c.session} gap={1}>
            <Text wrap="truncate-end">
              {c.topic || c.ws_title || c.last_title || c.session.slice(0, 8)} <Text dimColor>
                {c.state ?? '?'} {ago(now - (c.ts ?? now))} {c.cwd?.split('/').at(-1) ?? ''}
              </Text>
            </Text>
            {c.session !== self && <Button key={`close-${c.session}`} label="Close up" onPress={() => closeUp(c.session)} />}
          </Box>
        ))}
      </Box>
    )
  })
}

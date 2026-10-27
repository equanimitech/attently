import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { markerOf } from './register'

// Synthetic stand-ins for contract/session-start.md and contract/turn.md.
const CONTRACT = '[attently] contract body\n\n## The press\n\n1. a page\n\n## The ask\n\nname it'
const TURN = '[attently] per-turn reminder'

const files: Record<string, string> = {
  'session-start.md': `${CONTRACT}\n`,
  'turn.md': `${TURN}\n`,
  'alpha.md': '# Alpha\n\nweighed and rejected',
}

// Answers every `$` call the mod makes beneath it; card writes are recorded, never stored.
const engine = (on: On) => {
  const writes: { path: string; text: string }[] = []
  mock.env(on, { HOME: '/home/synthetic' })
  mock.clock(on)
  on('session.id', () => ({ value: 's-synthetic' }))
  on('session.cwd', () => ({ value: '/w' }))
  on('fs.read', (_, e) => {
    const text = files[e.path.split('/').at(-1) ?? '']
    if (text === undefined) throw new Error(`ENOENT ${e.path}`)
    return { value: text }
  })
  on('fs.write', (_, e) => (writes.push(e), { value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('turn.complete', () => ({ text: '' }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  return writes
}

const band = {
  plugin: 'attently',
  component: 'AbovePrompt',
  surface: 'terminal',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 80, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const reply = (answer: string) =>
  ({ answer, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' }) as const

test('the marker is the last line when it opens with a check or a hand', () => {
  expect(markerOf('Did it.\n\n✓ shipped the band')).toBe('✓ shipped the band')
  expect(markerOf('Two ways.\n\n**✋ waiting on you: pick one**\n\n')).toBe('✋ waiting on you: pick one')
  expect(markerOf('> ✅ done')).toBe('✓ done')
  expect(markerOf('⏸ legacy wait')).toBe('✋ legacy wait')
  expect(markerOf('✓ not last\n\nmore after it')).toBe('')
  expect(markerOf('')).toBe('')
})

test('the shell contract stands down; the handoff lines and others stay; the section carries it', async ($, on) => {
  engine(on)
  on('classic.SessionStart', () => ({ additionalContext: [`${CONTRACT}\n\nResume brief: /tmp/b.md`, 'another plugin'] }))
  on('classic.UserPromptSubmit', () => ({ additionalContext: [`${TURN}\n[attently] context 151k`, 'another plugin'] }))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'engine intro', scope: 'shared' }] }))

  expect((await $.classic.SessionStart({ source: 'compact' })).additionalContext)
    .toEqual(['Resume brief: /tmp/b.md', 'another plugin'])
  expect((await $.classic.UserPromptSubmit({ prompt: 'hi' })).additionalContext)
    .toEqual(['[attently] context 151k', 'another plugin'])

  const { sections } = await $.prompt.compose({ model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] })
  expect(sections.map(s => s.id)).toEqual(['intro', 'attently:contract'])
  expect(sections[1]?.text).toContain('1. a page\n\nA stretch grows the claim; a page shows the work.\n\n## The ask')
})

test('band: marker glyph, configured replies, and opened / did-not-open on the next typed prompt', { options: { replies: 'Close up · Ship it' } }, async ($, on) => {
  const writes = engine(on)
  const submitted: { text: string; context?: readonly string[]; kind: string }[] = []
  on('prompt.submit', (_, e) => (submitted.push({ text: e.text, context: e.context, kind: e.origin.kind }), { text: e.text }))

  await $.turn.complete(reply('Two pages.\n\n/w/.claude/attently/alpha.md\n/w/.claude/attently/beta.md\n\n✓ wrote them'))
  expect(writes.at(-1)?.path).toBe('/home/synthetic/.claude/attently/ring/sessions/s-synthetic.json')
  expect(JSON.parse(writes.at(-1)?.text ?? '{}')).toMatchObject({ session: 's-synthetic', cwd: '/w', state: 'done', marker: '✓ wrote them' })

  const ui = await $.ui.mount(band)
  expect(await ui.find({ type: 'Text', text: '✓' })).toBeDefined()
  expect((await ui.find({ key: 'reply-1' }))?.text).toBe('Ship it')
  await ui.press({ key: 'open-/w/.claude/attently/alpha.md' })
  const page = await $.ui.mount({
    plugin: 'attently', component: 'Pane', requestId: 'attently-page', surface: 'terminal',
    props: { title: 'alpha', isFocused: true, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
  })
  expect(await page.find({ type: 'Markdown', text: /weighed and rejected/ })).toBeDefined()
  await page.unmount()

  // A press is not a typed prompt: it submits exactly its text and reports nothing.
  await ui.press({ key: 'reply-0' })
  expect(submitted.at(-1)).toEqual({ text: 'Close up', context: undefined, kind: 'plugin' })
  await ui.unmount()

  await $.prompt.submit({ text: 'next', origin: { kind: 'composer' }, wait: false })
  expect(submitted.at(-1)?.context).toEqual(['attently: the reader opened alpha\nattently: the reader did not open beta'])
  await $.prompt.submit({ text: 'again', origin: { kind: 'composer' }, wait: false })
  expect(submitted.at(-1)?.context).toBeUndefined()
})

test('/ring lists cards with state and age; Close up sends to that session', async ($, on) => {
  engine(on)
  files['peer.json'] = JSON.stringify({ session: 'peer', cwd: '/w/repo', state: 'waiting', ts: 0, topic: 'synthetic topic', surface: 'x' })
  files['s-synthetic.json'] = JSON.stringify({ session: 's-synthetic', cwd: '/w', state: 'working', ts: 0 })
  on('fs.list', () => ({ value: ['peer.json', 's-synthetic.json'].map(name => ({ name, kind: 'file', size: 1, mtimeMs: 0, isLink: false })) }))
  on('command.register', () => ({ value: { command: 'ring' } }))
  const sent: unknown[] = []
  on('session.send', (_, e) => (sent.push({ to: e.to, text: e.text }), { isDelivered: true }))

  await $.command.run({ command: 'ring', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'attently', component: 'Pane', requestId: 'attently-ring', surface,
      props: { title: 'Ring', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
    })
    expect(await ui.find({ type: 'Text', text: /synthetic topic/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /waiting \d+[smhd] repo/ })).toBeDefined()
    expect(await ui.find({ key: 'close-s-synthetic' })).toBeUndefined()
    await ui.press({ key: 'close-peer' })
    await ui.unmount()
  }
  expect(sent[0]).toMatchObject({ text: "Please run /close-up to land this session's progress." })
})

test('no band while a turn runs; what draws beneath still shows', async ($, on) => {
  engine(on)
  await $.turn.complete(reply('✋ waiting on you: which'))
  const working = await $.ui.mount({ ...band, props: { ...band.props, isWorking: true } })
  expect(await working.find({ key: 'reply-0' })).toBeUndefined()
  expect(await working.find({ type: 'Text', text: 'engine' })).toBeDefined()
  await working.unmount()
})

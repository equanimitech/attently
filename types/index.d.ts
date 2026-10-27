// A wiki page the last reply linked, and whether the reader opened it.
export type Page = { name: string; path: string; isOpened: boolean }

// A ring card as ring.sh and the mod write it; the mod writes only the first five fields.
export type Card = {
  session: string
  cwd?: string
  state?: string
  marker?: string
  ts?: number
  topic?: string
  ws_title?: string
  last_title?: string
}

declare module 'claude-code' {
  interface PluginState {
    attently: {
      // The last main-loop turn's marker line ('' for none); null once the next turn starts.
      turn: Shaped<string | null>
      isTyping: boolean
      pages: Shaped<Page[]>
      shown: Shaped<{ name: string; text: string } | null>
      cards: Shaped<Card[]>
    }
  }
}

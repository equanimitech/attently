// attently ring -- Glance, Ask, Click over the Claude sessions in cmux.
//
// Top to bottom: ◉ Sauron (Click, ring-wide: settle what waits on you), the loops (Glance: ✋
// waiting on you and ✓ done and not yet seen, oldest first, then …N subagents still running;
// tap one to go to its tab), then every workspace in cmux order with all its tabs, one muted
// line each (ring tabs ◉ → ◎ → ○, then the rest). A workspace header carries its Clicks: the
// ritual lever on the area that owns the day-phase's ritual (loud only while it is due), and
// + Claude (a new tab running claude in the workspace's folder).
//
// Reads only live cmux state: tab titles and workspace descriptions are the whole bridge from
// the attently hooks (cmux's `agents` field is empty on the builds we run). A ring tab's title
// opens with its layer glyph (◉ focus, ◎ secondary, ○ background) and state glyph, e.g.
// "○✋ Claude Code"; a tab with no ring glyph is not in the ring. A workspace description opens
// with the ring's lines, "◌ " then either a loop, "<glyph> <since epoch> <tab name> · <clause>"
// (glyph ✋, ✓ or …N), or a ritual lever, "☀️ Sunrise ready" while due, "☀️ Sunrise" otherwise.
// 🔊 / 🔉 / 🔇 and ⏸ are still read: tabs painted before 0.4.1 keep them until their next turn.

func desc(_ w) -> String {
  return w.description != nil ? w.description : ""
}

// The ring's lines of a workspace description, without their "◌ ".
func ringLines(_ w) -> [Any] {
  return desc(w).split(separator: "\n").filter { $0.hasPrefix("◌ ") }.map { $0.dropFirst(2) }
}

// Word i of a line, split on single spaces.
func word(_ s, _ i) -> String {
  let parts = s.split(separator: " ")
  return parts.count > i ? parts[i] : ""
}

func isLoop(_ l) -> Bool {
  let g = word(l, 0)
  return g == "✋" || g == "✓" || g.hasPrefix("…")
}

func ritualOf(_ l) -> String {
  if l.contains("Sunrise") { return "sunrise" }
  if l.contains("Midday") { return "midday" }
  if l.contains("Sunset") { return "sunset" }
  return ""
}

// The ring mark of a tab: "◉✋" of "◉✋ leggia".
func markOf(_ a) -> String {
  let parts = a.title.split(separator: " ")
  return parts.count > 0 ? parts.first : ""
}

// The tab name without its ring mark: "leggia" of "◉✋ leggia".
func nameOf(_ a) -> String {
  if layerOf(a) == "" { return a.title }
  let rest = a.title.dropFirst(markOf(a).count + 1)
  return rest.count > 0 ? rest : a.title
}

func layerOf(_ a) -> String {
  let m = markOf(a)
  if m.hasPrefix("◉") || m.hasPrefix("🔊") { return "focus" }
  if m.hasPrefix("◎") || m.hasPrefix("🔉") { return "secondary" }
  if m.hasPrefix("○") || m.hasPrefix("🔇") { return "background" }
  return ""
}

func waiting(_ a) -> Bool {
  return markOf(a).contains("✋") || markOf(a).contains("⏸")
}

// A loop of the whole ring is "<workspace id> <glyph> <since> <tab name> · <clause>". Sort key:
// its since, running subagents after every ✋ and ✓.
func loopKey(_ e) -> Int {
  return (word(e, 1).hasPrefix("…") ? 10000000000 : 0) + Int(word(e, 2))
}

func loopLabel(_ g, _ ago, _ area, _ clause) -> some View {
  HStack(spacing: 6) {
    Text(g).font(.system(size: 11)).foregroundColor(.accent)
    Text(ago).font(.system(size: 10)).monospacedDigit().foregroundColor(.secondary)
    Text("\(area) · \(clause)").font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
    Spacer()
  }
  .padding(4)
  .background { RoundedRectangle(cornerRadius: 6).foregroundColor(.accent).opacity(0.08) }
}

// Tap goes to the loop's tab, matched by its name within the workspace; else to the workspace.
func loopRow(_ e) -> some View {
  let w = workspaces.filter { $0.id == word(e, 0) }.first
  let rest = e.dropFirst(word(e, 0).count + word(e, 1).count + word(e, 2).count + 3)
  let hits = w.tabs.filter { $0.surfaceId != nil && rest.hasPrefix("\(nameOf($0)) · ") }
  let clause = hits.count > 0 ? rest.dropFirst(nameOf(hits.first).count + 3) : rest
  let age = Int(clock.epoch) - Int(word(e, 2))
  let ago = age < 3600 ? "\(Int(age / 60))m" : "\(Int(age / 3600))h"
  return VStack(alignment: .leading, spacing: 0) {
    if hits.count > 0 {
      Button(action: {
        cmux("workspace.select", workspace_id: w.id)
        cmux("surface.focus", surface_id: hits.first.surfaceId, workspace_id: w.id)
      }) { loopLabel(word(e, 1), ago, w.title, clause) }
    } else {
      Button(action: { cmux("workspace.select", workspace_id: w.id) }) { loopLabel(word(e, 1), ago, w.title, clause) }
    }
  }
}

func tabRow(_ w, _ t) -> some View {
  Button(action: {
    cmux("workspace.select", workspace_id: w.id)
    cmux("surface.focus", surface_id: t.surfaceId, workspace_id: w.id)
  }) {
    HStack(spacing: 6) {
      Text(waiting(t) ? "✋" : "·").font(.system(size: 10)).foregroundColor(.tertiary)
      Text(nameOf(t)).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
      Spacer()
    }
    .padding(3)
  }
}

// A ritual lever opens the ritual in a new tab of its area's workspace.
func lever(_ w, _ l) -> some View {
  Button(action: {
    cmux("workspace.select", workspace_id: w.id)
    cmux("surface.create", workspace_id: w.id, initial_input: "'__ATTENTLY_RING__' ritual \(ritualOf(l)) --here\n", focus: true)
  }) {
    Text(l)
      .font(.system(size: 10))
      .foregroundColor(l.hasSuffix("ready") ? .accent : .secondary)
      .padding(2)
      .background { RoundedRectangle(cornerRadius: 4).foregroundColor(.accent).opacity(l.hasSuffix("ready") ? 0.15 : 0) }
  }
}

func area(_ w) -> some View {
  let levers = ringLines(w).filter { !isLoop($0) && ritualOf($0) != "" }
  return VStack(alignment: .leading, spacing: 2) {
    HStack(spacing: 6) {
      if let c = w.color {
        Circle().frame(width: 7, height: 7).foregroundColor(c)
      } else {
        Circle().frame(width: 7, height: 7).foregroundColor(.tertiary)
      }
      Button(action: { cmux("workspace.select", workspace_id: w.id) }) {
        Text(w.title).font(.system(size: 12)).bold().lineLimit(1).truncationMode(.tail)
      }
      Spacer()
      ForEach(levers) { l in lever(w, l) }
      Button(action: {
        cmux("workspace.select", workspace_id: w.id)
        cmux("surface.create", workspace_id: w.id, working_directory: w.directory, initial_input: "claude\n", focus: true)
      }) {
        Text("+ Claude").font(.system(size: 10)).foregroundColor(.secondary)
      }
    }
    ForEach(w.tabs.filter { layerOf($0) == "focus" }) { t in tabRow(w, t) }
    ForEach(w.tabs.filter { layerOf($0) == "secondary" }) { t in tabRow(w, t) }
    ForEach(w.tabs.filter { layerOf($0) == "background" }) { t in tabRow(w, t) }
    ForEach(w.tabs.filter { layerOf($0) == "" }) { t in tabRow(w, t) }
  }
  .padding(4)
  .background { RoundedRectangle(cornerRadius: 6).foregroundColor(.primary).opacity(w.selected ? 0.06 : 0) }
}

func sauronLabel() -> some View {
  HStack {
    Text("◉ Sauron").font(.system(size: 12)).bold()
    Spacer()
  }
  .padding(4)
}

ScrollView {
  VStack(alignment: .leading, spacing: 6) {
    let sauron = workspaces.filter { $0.title == "👁 Sauron" }
    if sauron.count > 0 {
      Button(action: { cmux("workspace.select", workspace_id: sauron.first.id) }) { sauronLabel() }
    } else {
      Button(action: { cmux("workspace.create", title: "👁 Sauron", initial_input: "'__ATTENTLY_RING__' sauron --here\n", focus: true) }) { sauronLabel() }
    }

    let loops = workspaces.flatMap { w in ringLines(w).filter { isLoop($0) }.map { "\(w.id) \($0)" } }.sorted { loopKey($0) < loopKey($1) }
    if loops.count > 0 {
      Text("Loops").font(.system(size: 10)).foregroundColor(.tertiary).padding(4)
      ForEach(loops) { e in loopRow(e) }
    }
    Divider()

    ForEach(workspaces) { w in area(w) }
    Spacer()
  }
  .padding(6)
}

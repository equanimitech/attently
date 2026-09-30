// attently ring -- your areas, and the Claude tabs inside each, ranked by what deserves you now.
//
// Center to periphery. Each workspace is an area. Inside it, focus tabs get a full row until
// you have seen their finished turn, then one muted line like secondary tabs; background tabs
// collapse into one menu. Tap a tab to focus it.
// While a day-phase ritual waits for you, one ritual row sits on top; nothing opens until you
// tap it.
//
// Reads only live cmux state, and only tab titles and workspace descriptions: cmux's `agents`
// field is empty on the builds we run, so the attently hooks' painting is the whole bridge.
// A ring tab's title opens with its layer glyph (◉ focus, ◎ secondary, ○ background) and its
// state glyph (✋ waiting on you, … working, …2 two subagents still running, ✓ done and not yet
// seen, none once seen), e.g. "○✋ Claude Code"; a workspace
// description opens with its area rollup ("◉ DC · 2 waiting on you"). A tab with no ring glyph
// is not in the ring (sessions started before the plugin was installed stay unpainted).
// 🔊 / 🔉 / 🔇 and ⏸ are still read: tabs painted before 0.4.1 keep them until their next turn.

func desc(_ w) -> String {
  return w.description != nil ? w.description : ""
}

func rollup(_ w) -> String {
  let lines = desc(w).split(separator: "\n")
  return lines.count > 0 ? lines.first : ""
}

// The ring mark of a tab: "◉✋" of "◉✋ leggia".
func markOf(_ a) -> String {
  let parts = a.title.split(separator: " ")
  return parts.count > 0 ? parts.first : ""
}

func layerOf(_ a) -> String {
  let m = markOf(a)
  if m.hasPrefix("◉") || m.hasPrefix("🔊") { return "focus" }
  if m.hasPrefix("◎") || m.hasPrefix("🔉") { return "secondary" }
  if m.hasPrefix("○") || m.hasPrefix("🔇") { return "background" }
  return ""
}

func claudes(_ w) -> [Any] {
  return w.tabs.filter { layerOf($0) != "" }
}

func areaRank(_ w) -> Int {
  let r = rollup(w)
  if r.hasPrefix("◉") { return 1 }
  if r.hasPrefix("🔊") { return 1 }
  if r.hasPrefix("◎") { return 2 }
  if r.hasPrefix("🔉") { return 2 }
  return 3
}

func waiting(_ a) -> Bool {
  return markOf(a).contains("✋") || markOf(a).contains("⏸")
}

// No state glyph: the reader has seen the finished turn, so the row goes quiet.
func settled(_ a) -> Bool {
  let m = markOf(a)
  return !waiting(a) && !m.contains("…") && !m.contains("✓")
}

// "◉…2" -> "… 2 agents running".
func stateText(_ a) -> String {
  if waiting(a) { return "✋ waiting on you" }
  let n = markOf(a).split(separator: "…")
  if markOf(a).contains("…") && n.count > 1 { return n.last == "1" ? "… 1 agent running" : "… \(n.last) agents running" }
  if markOf(a).contains("…") { return "… working" }
  return "✓ done"
}

func ritualOf(_ d) -> String {
  if d.contains("☀️ Sunrise ready") { return "sunrise" }
  if d.contains("🥗 Midday ready") { return "midday" }
  if d.contains("🌙 Sunset ready") { return "sunset" }
  return ""
}

func ritualLabel(_ r) -> String {
  if r == "sunrise" { return "☀️ Sunrise ready" }
  if r == "midday" { return "🥗 Midday ready" }
  return "🌙 Sunset ready"
}

func focusRow(_ w, _ a) -> some View {
  Button(action: {
    cmux("workspace.select", workspace_id: w.id)
    cmux("surface.focus", surface_id: a.surfaceId)
  }) {
    HStack(alignment: .top, spacing: 7) {
      Capsule().frame(width: 3, height: 30).foregroundColor("#3B82F6")
      VStack(alignment: .leading, spacing: 2) {
        Text(a.title).font(.system(size: 12)).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
        Text(stateText(a))
          .font(.system(size: 11))
          .foregroundColor(waiting(a) ? "#3B82F6" : .secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(5)
    .background { RoundedRectangle(cornerRadius: 6).foregroundColor("#3B82F6").opacity(w.selected ? 0.16 : 0.06) }
  }
}

func secondaryRow(_ w, _ a) -> some View {
  Button(action: {
    cmux("workspace.select", workspace_id: w.id)
    cmux("surface.focus", surface_id: a.surfaceId)
  }) {
    HStack(spacing: 6) {
      Text(waiting(a) ? "✋" : "·").font(.system(size: 10)).foregroundColor("#8B9DC3")
      Text(a.title).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
      Spacer()
    }
    .padding(3)
  }
}

func area(_ w) -> some View {
  let tabs = claudes(w)
  let focus = tabs.filter { layerOf($0) == "focus" }
  let secondary = tabs.filter { layerOf($0) == "secondary" }
  let background = tabs.filter { layerOf($0) == "background" }
  let backgroundWaiting = background.filter { waiting($0) }
  return VStack(alignment: .leading, spacing: 3) {
    Button(action: { cmux("workspace.select", workspace_id: w.id) }) {
      HStack(spacing: 6) {
        Circle().frame(width: 7, height: 7).foregroundColor(w.color != nil ? w.color : "#9CA3AF")
        Text(w.title).font(.system(size: 12)).bold().lineLimit(1).truncationMode(.tail)
        Spacer()
        Text(rollup(w)).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
      }
    }
    ForEach(focus.filter { waiting($0) }) { a in focusRow(w, a) }
    ForEach(focus.filter { !waiting($0) && !settled($0) }) { a in focusRow(w, a) }
    ForEach(focus.filter { settled($0) }) { a in secondaryRow(w, a) }
    ForEach(secondary.filter { waiting($0) }) { a in secondaryRow(w, a) }
    ForEach(secondary.filter { !waiting($0) }) { a in secondaryRow(w, a) }
    if background.count > 0 {
      Menu("○ \(background.count - backgroundWaiting.count) parked · \(backgroundWaiting.count) waiting") {
        ForEach(backgroundWaiting) { a in
          Button("✋ \(a.title)") {
            cmux("workspace.select", workspace_id: w.id)
            cmux("surface.focus", surface_id: a.surfaceId)
          }
        }
        ForEach(background.filter { !waiting($0) }) { a in
          Button(a.title) {
            cmux("workspace.select", workspace_id: w.id)
            cmux("surface.focus", surface_id: a.surfaceId)
          }
        }
      }
      .font(.system(size: 11))
      .foregroundColor("#6B7280")
    }
  }
  .padding(4)
}

VStack(alignment: .leading, spacing: 6) {
  HStack {
    Text("Ring").font(.system(size: 13)).bold()
    Spacer()
    Text(clock.time).font(.system(size: 10, design: .monospaced)).foregroundColor(.tertiary)
  }
  .padding(4)

  let ws = workspaces.prefix(60)
  let rituals = ws.filter { ritualOf(desc($0)) != "" }
  if rituals.count > 0 {
    let r = ritualOf(desc(rituals.first))
    Button(action: {
      cmux("workspace.create", title: "Ritual", initial_input: "'__ATTENTLY_RING__' ritual \(r) --here\n", focus: true)
    }) {
      HStack {
        Text(ritualLabel(r)).font(.system(size: 12))
        Spacer()
        Text("begin").font(.system(size: 10)).foregroundColor(.secondary)
      }
      .padding(6)
      .background { RoundedRectangle(cornerRadius: 6).foregroundColor("#F59E0B").opacity(0.10) }
    }
  }
  Divider()

  let areas = ws.filter { claudes($0).count > 0 }
  if areas.count == 0 {
    Text("No Claude sessions").font(.system(size: 11)).foregroundColor(.tertiary).padding(4)
  }
  ForEach(areas.filter { areaRank($0) == 1 }) { w in area(w) }
  ForEach(areas.filter { areaRank($0) == 2 }) { w in area(w) }
  ForEach(areas.filter { areaRank($0) == 3 }) { w in area(w) }
  Spacer()
}
.padding(6)

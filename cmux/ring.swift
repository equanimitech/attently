// attently ring -- your areas, and the Claude tabs inside each, ranked by what deserves you now.
//
// Center to periphery. Each workspace is an area. Inside it, focus tabs get a full row,
// secondary tabs one muted line, background tabs collapse into one menu. Tap a tab to focus it.
// While a day-phase ritual waits for you, one ritual row sits on top; nothing opens until you
// tap it.
//
// Reads only live cmux state. The attently hooks are the bridge: a Claude tab's title opens
// with its layer glyph (◉ focus, ◎ secondary, ○ background) and a workspace description with
// its area rollup ("◉ DC · 2 waiting on you"). Working / waiting / idle is cmux's own agent status.
// 🔊 / 🔉 are still read: tabs painted before 0.4.1 keep them until their session's next turn.

func desc(_ w) -> String {
  return w.description != nil ? w.description : ""
}

func rollup(_ w) -> String {
  let lines = desc(w).split(separator: "\n")
  return lines.count > 0 ? lines.first : ""
}

func claudes(_ w) -> [Any] {
  let all = w.agents != nil ? w.agents : []
  return all.filter { $0.kind == "claude" && $0.status != "ended" }
}

func titleOf(_ w, _ a) -> String {
  let ts = w.tabs.filter { $0.surfaceId == a.surfaceId }
  if ts.count > 0 { return ts.first.title }
  return a.title != nil ? a.title : a.name
}

func layerOf(_ w, _ a) -> String {
  let t = titleOf(w, a)
  if t.hasPrefix("◉") { return "focus" }
  if t.hasPrefix("🔊") { return "focus" }
  if t.hasPrefix("◎") { return "secondary" }
  if t.hasPrefix("🔉") { return "secondary" }
  return "background"
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
  return a.status == "needs_input"
}

func stateText(_ a) -> String {
  if a.status == "needs_input" { return "✋ waiting on you" }
  if a.status == "working" { return "… working" }
  return "✓ idle"
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
        Text(titleOf(w, a)).font(.system(size: 12)).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
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
      Text(titleOf(w, a)).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
      Spacer()
    }
    .padding(3)
  }
}

func area(_ w) -> some View {
  let tabs = claudes(w)
  let focus = tabs.filter { layerOf(w, $0) == "focus" }
  let secondary = tabs.filter { layerOf(w, $0) == "secondary" }
  let background = tabs.filter { layerOf(w, $0) == "background" }
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
    ForEach(focus.filter { !waiting($0) }) { a in focusRow(w, a) }
    ForEach(secondary.filter { waiting($0) }) { a in secondaryRow(w, a) }
    ForEach(secondary.filter { !waiting($0) }) { a in secondaryRow(w, a) }
    if background.count > 0 {
      Menu("○ \(background.count - backgroundWaiting.count) parked · \(backgroundWaiting.count) waiting") {
        ForEach(backgroundWaiting) { a in
          Button("✋ \(titleOf(w, a))") {
            cmux("workspace.select", workspace_id: w.id)
            cmux("surface.focus", surface_id: a.surfaceId)
          }
        }
        ForEach(background.filter { !waiting($0) }) { a in
          Button(titleOf(w, a)) {
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

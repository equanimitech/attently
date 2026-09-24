// attently ring -- the fleet at a glance: what deserves your attention now.
//
// Center to periphery. Focus sessions get full rows, secondary one muted line each,
// background collapses into one grey menu. Tap any row to jump to its workspace.
//
// Reads only live cmux state. The attently Stop hook is the bridge: it writes each
// workspace's description as "<layer glyph> <marker>" (🔊 focus, 🔉 secondary, 🔇 background)
// and its colour. A workspace the hook has not painted yet counts as background.

func desc(_ w) -> String {
  return w.description != nil ? w.description : ""
}

func layerOf(_ w) -> String {
  let d = desc(w)
  if d.hasPrefix("🔊") { return "focus" }
  if d.hasPrefix("🔉") { return "secondary" }
  return "background"
}

func isWaiting(_ w) -> Bool {
  return desc(w).contains("⏸")
}

func focusRow(_ w) -> some View {
  Button(action: { cmux("workspace.select", workspace_id: w.id) }) {
    HStack(alignment: .top, spacing: 7) {
      Capsule().frame(width: 3, height: 30).foregroundColor("#3B82F6")
      VStack(alignment: .leading, spacing: 2) {
        Text(w.title).font(.system(size: 12)).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
        Text(desc(w) == "🔊" ? "🔊 working" : desc(w))
          .font(.system(size: 11))
          .foregroundColor(isWaiting(w) ? "#3B82F6" : .secondary)
          .lineLimit(2).truncationMode(.tail)
      }
      Spacer()
    }
    .padding(5)
    .background { RoundedRectangle(cornerRadius: 6).foregroundColor("#3B82F6").opacity(w.selected ? 0.16 : 0.06) }
  }
}

func secondaryRow(_ w) -> some View {
  Button(action: { cmux("workspace.select", workspace_id: w.id) }) {
    HStack(spacing: 6) {
      Text(isWaiting(w) ? "⏸" : "·").font(.system(size: 10)).foregroundColor("#8B9DC3")
      Text(w.title).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
      Spacer()
    }
    .padding(3)
    .help(desc(w))
  }
}

VStack(alignment: .leading, spacing: 6) {
  HStack {
    Text("Ring").font(.system(size: 13)).bold()
    Spacer()
    Text(clock.time).font(.system(size: 10, design: .monospaced)).foregroundColor(.tertiary)
  }
  .padding(4)
  Divider()

  let ws = workspaces.prefix(80)
  let focus = ws.filter { layerOf($0) == "focus" }
  let secondary = ws.filter { layerOf($0) == "secondary" }
  let background = ws.filter { layerOf($0) == "background" }
  let backgroundWaiting = background.filter { isWaiting($0) }

  if focus.count == 0 {
    Text("Nothing in focus").font(.system(size: 11)).foregroundColor(.tertiary).padding(4)
  }
  ForEach(focus.filter { isWaiting($0) }) { w in focusRow(w) }
  ForEach(focus.filter { !isWaiting($0) }) { w in focusRow(w) }

  if secondary.count > 0 {
    Divider()
    ForEach(secondary.filter { isWaiting($0) }) { w in secondaryRow(w) }
    ForEach(secondary.filter { !isWaiting($0) }) { w in secondaryRow(w) }
  }

  if background.count > 0 {
    Divider()
    Menu("🔇 \(background.count - backgroundWaiting.count) parked · \(backgroundWaiting.count) waiting") {
      ForEach(backgroundWaiting) { w in
        Button("⏸ \(w.title)") { cmux("workspace.select", workspace_id: w.id) }
      }
      ForEach(background.filter { !isWaiting($0) }) { w in
        Button(w.title) { cmux("workspace.select", workspace_id: w.id) }
      }
    }
    .font(.system(size: 11))
    .foregroundColor("#6B7280")
    .padding(4)
  }
  Spacer()
}
.padding(6)

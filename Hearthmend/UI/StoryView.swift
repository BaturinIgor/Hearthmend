import SwiftUI

/// История деревни: короткие сцены с жителями, когда открывается и отстраивается район.
/// Реплики в строках story.<район>.<intro|done>.<n>, кто говорит - в таблице ниже.
enum Story {
    static let speakers: [String: [String]] = [
        "square.intro": ["tim", "tim"],
        "square.done": ["mila"],
        "farmstead.intro": ["tim"],
        "farmstead.done": ["chloe"],
        "riverside.intro": ["tim", "fin"],
        "riverside.done": ["fin"],
        "orchard.intro": ["tim", "katy"],
        "orchard.done": ["katy"],
        "hilltop.intro": ["mila", "tim"],
        "hilltop.done": ["mila"],
        "mine.intro": ["mike", "bruno"],
        "mine.done": ["bruno"],
        "fair.intro": ["bruno", "chloe"],
        "fair.done": ["tim"],
    ]
}

/// Сцена: портрет жителя, имя и реплика в рамке. Тап - следующая реплика.
struct StoryView: View {
    let scene: String
    let close: () -> Void
    @State private var line = 0
    @State private var shown = false

    var body: some View {
        let speakers = Story.speakers[scene] ?? []
        let who = speakers.indices.contains(line) ? speakers[line] : "tim"
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture(perform: next)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ResidentIcon(id: who, size: 56)
                        .padding(4)
                        .background(PixelSlice(key: "ui_paper_gold", inset: 4))
                        .id(who)
                        .transition(.scale.combined(with: .opacity))
                    Text(L10n.t("resident.\(who)"))
                        .font(Pixel.font(20))
                    Spacer()
                    Text("\(line + 1)/\(max(1, speakers.count))")
                        .font(Pixel.font(13))
                        .opacity(0.6)
                }
                Text(L10n.t("story.\(scene).\(line + 1)"))
                    .font(Pixel.font(16))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line)
                    .transition(.opacity)
                HStack {
                    Spacer()
                    Button(action: next) {
                        Text(L10n.t(line + 1 < speakers.count ? "story.next" : "story.ok"))
                    }
                    .buttonStyle(PixelButtonStyle(kind: .green, size: 16, compact: true))
                }
            }
            .foregroundColor(Theme.text)
            .padding(16)
            .background(PixelSlice(key: "ui_panel", inset: 6))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
            .offset(y: shown ? 0 : 300)
            .onTapGesture(perform: next)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: line)
        .onAppear {
            Haptics.light()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = true }
        }
    }

    private func next() {
        Haptics.light()
        if line + 1 < (Story.speakers[scene]?.count ?? 1) {
            line += 1
        } else {
            withAnimation(.easeIn(duration: 0.2)) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: close)
        }
    }
}

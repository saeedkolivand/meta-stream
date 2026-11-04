import SwiftUI

extension NewWidget {
    /// Tile colour in the picker.
    var tint: Color {
        switch self {
        case .chat: .blue
        case .alerts: .pink
        case .events: .purple
        case .clock, .liveTime, .viewers, .drive, .socials, .text: .teal
        case .nowPlaying: .green
        case .goal: .orange
        case .qr: .indigo
        case .image, .web: .yellow
        }
    }

    /// The picker's sections, in order.
    static let groups: [(title: String, kinds: [NewWidget])] = [
        ("Chat & alerts", [.chat, .alerts, .events]),
        ("Live info", [.clock, .liveTime, .viewers, .drive, .socials, .text]),
        ("Music & money", [.nowPlaying, .goal, .qr]),
        ("Media", [.image, .web])
    ]
}

/// The "+" picker: widgets grouped by what they do, each a coloured tile. The editor runs the add flow after the sheet
/// has gone (image needs the photo picker, web a URL alert), so `pick` only reports the choice.
struct AddWidgetGallery: View {
    let pick: (NewWidget) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(NewWidget.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(group.kinds, id: \.self) { tile($0) }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Add widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func tile(_ kind: NewWidget) -> some View {
        Button {
            pick(kind)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.icon).font(.title2).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: 14))
                Text(kind.title).font(.caption).foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

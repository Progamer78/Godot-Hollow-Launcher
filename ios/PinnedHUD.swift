import SwiftUI

struct HollowPinnedHUD: View {
    let rows: [PinnedReadout]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.caption2).foregroundColor(.white.opacity(0.7))
                        .lineLimit(1).truncationMode(.middle)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if row.frozen { Image(systemName: "snowflake").foregroundColor(.cyan).accessibilityLabel("Frozen") }
                        Text(row.value).font(.system(.caption, design: .monospaced).bold())
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                    }
                }
            }
        }.padding(10).frame(maxWidth: 240, alignment: .leading).foregroundColor(.white)
            .background(Color.black.opacity(0.75)).cornerRadius(12).accessibilityElement(children: .combine)
    }
}

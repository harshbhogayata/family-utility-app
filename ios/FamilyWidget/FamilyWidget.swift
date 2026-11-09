// 112 Widgets: Family home-screen (iOS 15+) and Lock Screen (iOS 16+) widgets.
// Reads the snapshot the app writes into the shared App Group defaults; no
// network. Taps open the app on familyapp://widget/<action>.
import SwiftUI
import UIKit
import WidgetKit

private let appGroup = "group.app.family.familyUtilityApp"

struct FamilyEntry: TimelineEntry {
  let date: Date
  let medicineTitle: String
  let medicineDetail: String
  let dial: [(label: String, number: String)]
}

private func readEntry() -> FamilyEntry {
  let d = UserDefaults(suiteName: appGroup)
  let title = d?.string(forKey: "medicine_title") ?? "No medicine due"
  let detail = d?.string(forKey: "medicine_detail") ?? ""
  var dial: [(label: String, number: String)] = []
  for i in 0..<3 {
    let label = d?.string(forKey: "dial_\(i)_label") ?? ""
    let number = d?.string(forKey: "dial_\(i)_number") ?? ""
    if !label.isEmpty && !number.isEmpty {
      dial.append((label: label, number: number))
    }
  }
  return FamilyEntry(date: Date(), medicineTitle: title, medicineDetail: detail, dial: dial)
}

struct FamilyProvider: TimelineProvider {
  func placeholder(in context: Context) -> FamilyEntry {
    FamilyEntry(date: Date(), medicineTitle: "No medicine due", medicineDetail: "", dial: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (FamilyEntry) -> Void) {
    completion(readEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyEntry>) -> Void) {
    let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    completion(Timeline(entries: [readEntry()], policy: .after(next)))
  }
}

private let scanURL = URL(string: "familyapp://widget/scan")!
private let pasteURL = URL(string: "familyapp://widget/paste")!
private let medicineURL = URL(string: "familyapp://widget/medicine")!

struct FamilyWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: FamilyEntry

  private var medicineLine: String {
    entry.medicineDetail.isEmpty ? entry.medicineTitle : "\(entry.medicineTitle) · \(entry.medicineDetail)"
  }

  var body: some View {
    content.familyWidgetBackground()
  }

  @ViewBuilder
  private var content: some View {
    switch family {
    case .systemSmall:
      VStack(alignment: .leading, spacing: 6) {
        Label(entry.medicineTitle, systemImage: "pills")
          .font(.footnote)
          .lineLimit(2)
        if !entry.medicineDetail.isEmpty {
          Text(entry.medicineDetail).font(.caption2).foregroundColor(.secondary)
        }
        Spacer()
        Label("Scan", systemImage: "doc.viewfinder").font(.headline)
      }
      .padding()
      .widgetURL(scanURL)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Scan. Next medicine: \(medicineLine)")
    default:
      bodyForAccessory
    }
  }

  @ViewBuilder
  private var bodyForAccessory: some View {
    if #available(iOSApplicationExtension 16.0, *) {
      switch family {
      case .accessoryCircular:
        Image(systemName: "doc.viewfinder")
          .font(.title2)
          .widgetURL(scanURL)
          .accessibilityLabel("Scan")
      case .accessoryInline:
        Label(medicineLine, systemImage: "pills")
          .widgetURL(medicineURL)
      case .accessoryRectangular:
        VStack(alignment: .leading) {
          Label("Next medicine", systemImage: "pills").font(.caption)
          Text(medicineLine).font(.headline).lineLimit(2)
        }
        .widgetURL(medicineURL)
        .accessibilityElement(children: .combine)
      default:
        medium
      }
    } else {
      medium
    }
  }

  private var medium: some View {
    VStack(alignment: .leading, spacing: 8) {
      Link(destination: medicineURL) {
        Label(medicineLine, systemImage: "pills").font(.subheadline).lineLimit(2)
      }
      .accessibilityLabel("Next medicine: \(medicineLine)")
      HStack(spacing: 8) {
        Link(destination: scanURL) { pill("Scan", "doc.viewfinder") }
        Link(destination: pasteURL) { pill("Paste", "doc.on.clipboard") }
      }
      HStack(spacing: 8) {
        ForEach(0..<entry.dial.count, id: \.self) { i in
          if let url = URL(string: "tel:\(entry.dial[i].number)") {
            Link(destination: url) { pill(entry.dial[i].label, "phone") }
              .accessibilityLabel("Call \(entry.dial[i].label)")
          }
        }
      }
    }
    .padding()
  }

  private func pill(_ title: String, _ symbol: String) -> some View {
    Label(title, systemImage: symbol)
      .font(.footnote)
      .lineLimit(1)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(Color(UIColor.secondarySystemBackground))
      .clipShape(Capsule())
  }
}

extension View {
  /// iOS 17 asks widgets to declare their background.
  @ViewBuilder
  func familyWidgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { Color.clear }
    } else {
      self
    }
  }
}

@main
struct FamilyWidget: Widget {
  let kind = "FamilyWidget"

  private var families: [WidgetFamily] {
    if #available(iOSApplicationExtension 16.0, *) {
      return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
    }
    return [.systemSmall, .systemMedium]
  }

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FamilyProvider()) { entry in
      FamilyWidgetView(entry: entry)
    }
    .configurationDisplayName("Family")
    .description("Scan, paste, speed dial and your next medicine.")
    .supportedFamilies(families)
  }
}

import SwiftUI

/// A lightweight sparkline chart that draws a line from data points.
struct SparklineView: View {
    let dataPoints: [Double]
    let color: Color
    let lineWidth: CGFloat

    init(dataPoints: [Double], color: Color = .accentColor, lineWidth: CGFloat = 1.5) {
        self.dataPoints = dataPoints
        self.color = color
        self.lineWidth = lineWidth
    }

    var body: some View {
        GeometryReader { geo in
            if dataPoints.count >= 2 {
                sparklinePath(in: geo.size)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            } else {
                Text("--")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sparklinePath(in size: CGSize) -> Path {
        let maxVal = dataPoints.max() ?? 1
        let minVal = dataPoints.min() ?? 0
        let range = maxVal - minVal
        let effectiveRange = range > 0 ? range : 1

        let stepX = size.width / CGFloat(dataPoints.count - 1)

        return Path { path in
            for (index, value) in dataPoints.enumerated() {
                let x = CGFloat(index) * stepX
                let normalizedY = (value - minVal) / effectiveRange
                let y = size.height - (CGFloat(normalizedY) * size.height)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }
}

import SwiftUI
import Foundation

enum LineIconKind {
    case overview
    case proxy
    case settings
    case cpu
    case memory
    case hardware
    case devices
    case ports
    case shield
    case trend
    case system
    case flash
    case thermometer
    case fan
}

/// Hand-drawn 24 x 24 line icons. Using one drawing routine keeps navigation,
/// card headers and hardware icons visually consistent.
struct LineIcon: View {
    let kind: LineIconKind
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            context.scaleBy(x: scale, y: scale)

            var path = Path()
            switch kind {
            case .overview:
                for x in [3.0, 13.0] {
                    for y in [3.0, 13.0] {
                        path.addRoundedRect(
                            in: CGRect(x: x, y: y, width: 8, height: 8),
                            cornerSize: CGSize(width: 2, height: 2)
                        )
                    }
                }

            case .proxy:
                path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
                path.addEllipse(in: CGRect(x: 8, y: 3, width: 8, height: 18))
                path.move(to: CGPoint(x: 3, y: 12))
                path.addLine(to: CGPoint(x: 21, y: 12))

            case .settings:
                for (y, knob) in [(6.0, 9.0), (12.0, 15.0), (18.0, 7.0)] {
                    path.move(to: CGPoint(x: 3, y: y))
                    path.addLine(to: CGPoint(x: 21, y: y))
                    path.addEllipse(in: CGRect(x: knob - 2, y: y - 2, width: 4, height: 4))
                }

            case .cpu:
                path.addRoundedRect(
                    in: CGRect(x: 6, y: 6, width: 12, height: 12),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.addRoundedRect(
                    in: CGRect(x: 9, y: 9, width: 6, height: 6),
                    cornerSize: CGSize(width: 1, height: 1)
                )
                for x in [9.0, 12.0, 15.0] {
                    path.move(to: CGPoint(x: x, y: 2))
                    path.addLine(to: CGPoint(x: x, y: 6))
                    path.move(to: CGPoint(x: x, y: 18))
                    path.addLine(to: CGPoint(x: x, y: 22))
                }
                for y in [9.0, 12.0, 15.0] {
                    path.move(to: CGPoint(x: 2, y: y))
                    path.addLine(to: CGPoint(x: 6, y: y))
                    path.move(to: CGPoint(x: 18, y: y))
                    path.addLine(to: CGPoint(x: 22, y: y))
                }

            case .memory:
                path.addRoundedRect(
                    in: CGRect(x: 4, y: 6, width: 16, height: 12),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.move(to: CGPoint(x: 4, y: 10))
                path.addLine(to: CGPoint(x: 20, y: 10))
                for x in [7.0, 11.0, 15.0, 19.0] {
                    path.move(to: CGPoint(x: x, y: 3))
                    path.addLine(to: CGPoint(x: x, y: 6))
                    path.move(to: CGPoint(x: x, y: 18))
                    path.addLine(to: CGPoint(x: x, y: 21))
                }

            case .hardware:
                path.addRoundedRect(
                    in: CGRect(x: 10, y: 3, width: 4, height: 12),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.addEllipse(in: CGRect(x: 7, y: 13, width: 10, height: 10))
                path.move(to: CGPoint(x: 12, y: 16))
                path.addLine(to: CGPoint(x: 12, y: 21))

            case .devices:
                path.addRoundedRect(
                    in: CGRect(x: 3, y: 5, width: 12, height: 10),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.addRoundedRect(
                    in: CGRect(x: 14, y: 9, width: 7, height: 11),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.move(to: CGPoint(x: 6, y: 18))
                path.addLine(to: CGPoint(x: 11, y: 18))

            case .ports:
                path.addRoundedRect(
                    in: CGRect(x: 3, y: 7, width: 18, height: 10),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.move(to: CGPoint(x: 7, y: 10))
                path.addLine(to: CGPoint(x: 7, y: 14))
                path.move(to: CGPoint(x: 12, y: 10))
                path.addLine(to: CGPoint(x: 12, y: 14))
                path.move(to: CGPoint(x: 17, y: 10))
                path.addLine(to: CGPoint(x: 17, y: 14))

            case .shield:
                path.move(to: CGPoint(x: 12, y: 3))
                path.addLine(to: CGPoint(x: 20, y: 6))
                path.addLine(to: CGPoint(x: 20, y: 12))
                path.addCurve(
                    to: CGPoint(x: 12, y: 21),
                    control1: CGPoint(x: 20, y: 17),
                    control2: CGPoint(x: 16, y: 20)
                )
                path.addCurve(
                    to: CGPoint(x: 4, y: 12),
                    control1: CGPoint(x: 8, y: 20),
                    control2: CGPoint(x: 4, y: 17)
                )
                path.addLine(to: CGPoint(x: 4, y: 6))
                path.closeSubpath()

            case .trend:
                path.move(to: CGPoint(x: 3, y: 3))
                path.addLine(to: CGPoint(x: 3, y: 21))
                path.addLine(to: CGPoint(x: 21, y: 21))
                path.move(to: CGPoint(x: 6, y: 16))
                path.addLine(to: CGPoint(x: 10, y: 11))
                path.addLine(to: CGPoint(x: 14, y: 14))
                path.addLine(to: CGPoint(x: 20, y: 7))

            case .system:
                path.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
                path.move(to: CGPoint(x: 12, y: 10))
                path.addLine(to: CGPoint(x: 12, y: 16))
                path.addEllipse(in: CGRect(x: 11.3, y: 7.3, width: 1.4, height: 1.4))

            case .flash:
                path.addRoundedRect(
                    in: CGRect(x: 4, y: 6, width: 16, height: 12),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.move(to: CGPoint(x: 7, y: 10))
                path.addLine(to: CGPoint(x: 17, y: 10))
                path.move(to: CGPoint(x: 7, y: 14))
                path.addLine(to: CGPoint(x: 12, y: 14))

            case .thermometer:
                path.addRoundedRect(
                    in: CGRect(x: 10, y: 3, width: 4, height: 12),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                path.addEllipse(in: CGRect(x: 7, y: 13, width: 10, height: 10))
                path.move(to: CGPoint(x: 12, y: 16))
                path.addLine(to: CGPoint(x: 12, y: 21))

            case .fan:
                path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
                for angle in [0.0, 120.0, 240.0] {
                    let radians = angle * .pi / 180
                    let x = 12 + cos(radians) * 6
                    let y = 12 + sin(radians) * 6
                    path.move(to: CGPoint(x: 12, y: 12))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="${HOME}/Library/Developer/Xcode/DerivedData/PCL.Mac-dlhwgbjhdpbbyxefezmtvujyakce"
APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/PCL.Mac.app"
DIST_DIR="${ROOT_DIR}/dist"
DMG_ROOT="${DIST_DIR}/dmgroot"
TEMP_DMG="${DIST_DIR}/PCL.Mac-Installer-Visual-temp.dmg"
FINAL_DMG="${DIST_DIR}/PCL.Mac-Installer-Visual.dmg"
BACKGROUND_PATH="${DMG_ROOT}/.background/installer-background.png"
BUILD_NUMBER="${CURRENT_PROJECT_VERSION:-}"

mkdir -p "${DIST_DIR}"
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}/.background"

BUILD_COMMAND=(xcodebuild build -project "${ROOT_DIR}/PCL.Mac.xcodeproj" -scheme "PCL.Mac" -configuration Release -destination 'platform=macOS')
if [[ -n "${BUILD_NUMBER}" ]]; then
  BUILD_COMMAND+=("CURRENT_PROJECT_VERSION=${BUILD_NUMBER}")
fi
"${BUILD_COMMAND[@]}"

codesign --force --sign - --deep "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

cp -R "${APP_PATH}" "${DMG_ROOT}/PCL.Mac.app"
ln -sfn /Applications "${DMG_ROOT}/Applications"

swift - <<SWIFT
import AppKit
import Foundation

let width = 800
let height = 520
let output = URL(fileURLWithPath: "${BACKGROUND_PATH}")

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let bg = NSRect(x: 0, y: 0, width: width, height: height)
NSColor(calibratedRed: 0.90, green: 0.95, blue: 0.99, alpha: 1).setFill()
bg.fill()

let softGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.00, alpha: 0.0),
    NSColor(calibratedRed: 0.78, green: 0.89, blue: 1.00, alpha: 0.22)
])!
softGradient.draw(in: bg, angle: 90)

ctx.saveGState()
ctx.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
ctx.fillEllipse(in: CGRect(x: -90, y: 300, width: 260, height: 260))
ctx.setFillColor(NSColor(calibratedRed: 0.52, green: 0.78, blue: 1.0, alpha: 0.12).cgColor)
ctx.fillEllipse(in: CGRect(x: 560, y: 40, width: 280, height: 280))
ctx.restoreGState()

let bannerRect = NSRect(x: 22, y: 22, width: 756, height: 476)
let banner = NSBezierPath(roundedRect: bannerRect, xRadius: 24, yRadius: 24)
NSColor.white.withAlphaComponent(0.38).setFill(); banner.fill()

let border = NSBezierPath(roundedRect: bannerRect, xRadius: 24, yRadius: 24)
border.lineWidth = 1
NSColor.white.withAlphaComponent(0.55).setStroke(); border.stroke()

func draw(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineSpacing = 3
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    text.draw(in: rect, withAttributes: attrs)
}

func drawBadge(_ text: String, rect: NSRect) {
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    NSColor.white.withAlphaComponent(0.95).setFill()
    path.fill()
    draw(text, rect: rect.offsetBy(dx: 0, dy: 6), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.62, alpha: 1), alignment: .center)
}

drawBadge("PCL.Mac Installer", rect: NSRect(x: 56, y: 430, width: 138, height: 28))
draw("安装 PCL.Mac", rect: NSRect(x: 56, y: 388, width: 340, height: 34), font: .systemFont(ofSize: 32, weight: .bold), color: NSColor(calibratedRed: 0.15, green: 0.23, blue: 0.34, alpha: 1))
draw("把左侧应用拖到右侧“应用程序”文件夹", rect: NSRect(x: 56, y: 352, width: 620, height: 26), font: .systemFont(ofSize: 18, weight: .semibold), color: NSColor(calibratedRed: 0.22, green: 0.33, blue: 0.46, alpha: 1))
draw("安装完成后，请从“应用程序”中启动。\n若系统提示安全确认，请在“应用程序”内再次打开一次。", rect: NSRect(x: 56, y: 308, width: 520, height: 44), font: .systemFont(ofSize: 14, weight: .regular), color: NSColor(calibratedRed: 0.38, green: 0.47, blue: 0.58, alpha: 1))

drawBadge("拖动安装", rect: NSRect(x: 86, y: 116, width: 170, height: 32))
drawBadge("Applications", rect: NSRect(x: 544, y: 116, width: 170, height: 32))

let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 292, y: 252))
arrow.curve(to: CGPoint(x: 510, y: 252), controlPoint1: CGPoint(x: 350, y: 248), controlPoint2: CGPoint(x: 450, y: 248))
arrow.lineWidth = 9
arrow.lineCapStyle = .round
NSColor(calibratedRed: 0.23, green: 0.60, blue: 0.95, alpha: 1).setStroke(); arrow.stroke()
let head = NSBezierPath()
head.move(to: CGPoint(x: 520, y: 252))
head.line(to: CGPoint(x: 486, y: 278))
head.line(to: CGPoint(x: 486, y: 226))
head.close()
NSColor(calibratedRed: 0.23, green: 0.60, blue: 0.95, alpha: 1).setFill(); head.fill()

draw("拖过去，就安装好了。", rect: NSRect(x: 280, y: 194, width: 244, height: 22), font: .systemFont(ofSize: 15, weight: .medium), color: NSColor(calibratedRed: 0.29, green: 0.41, blue: 0.55, alpha: 1), alignment: .center)

draw("PCL.Mac Installer", rect: NSRect(x: 56, y: 50, width: 220, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor(calibratedRed: 0.52, green: 0.58, blue: 0.66, alpha: 1))

ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.42).cgColor)
ctx.setLineWidth(1)
ctx.stroke(CGRect(x: 22, y: 22, width: 756, height: 476))

NSGraphicsContext.restoreGraphicsState()
let pngData = rep.representation(using: .png, properties: [:])!
try pngData.write(to: output)
SWIFT

rm -f "${TEMP_DMG}" "${FINAL_DMG}"
hdiutil create -srcfolder "${DMG_ROOT}" -volname "PCL.Mac" -fs HFS+ -format UDRW "${TEMP_DMG}"
ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}")
VOLUME_PATH=$(echo "${ATTACH_OUTPUT}" | awk '/\/Volumes\// {print substr($0, index($0,$3)); exit}')

cp "${BACKGROUND_PATH}" "${VOLUME_PATH}/.background/installer-background.png"

osascript <<APPLESCRIPT
tell application "Finder"
    tell folder (POSIX file "${VOLUME_PATH}")
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {120, 120, 920, 640}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:installer-background.png"
        set position of item "PCL.Mac.app" to {150, 250}
        set position of item "Applications" to {620, 250}
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "${VOLUME_PATH}"
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"
hdiutil verify "${FINAL_DMG}"
rm -f "${TEMP_DMG}"
rm -rf "${DMG_ROOT}"

echo "Installer ready: ${FINAL_DMG}"

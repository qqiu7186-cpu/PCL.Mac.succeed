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

mkdir -p "${DIST_DIR}"
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}/.background"

xcodebuild build -project "${ROOT_DIR}/PCL.Mac.xcodeproj" -scheme "PCL.Mac" -configuration Release -destination 'platform=macOS'

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
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.98, green: 0.985, blue: 0.992, alpha: 1),
    NSColor(calibratedRed: 0.95, green: 0.965, blue: 0.98, alpha: 1)
])!
gradient.draw(in: bg, angle: 90)

let card = NSBezierPath(roundedRect: NSRect(x: 26, y: 26, width: 748, height: 468), xRadius: 26, yRadius: 26)
NSColor.white.withAlphaComponent(0.9).setFill(); card.fill()
let border = NSBezierPath(roundedRect: NSRect(x: 26, y: 26, width: 748, height: 468), xRadius: 26, yRadius: 26)
border.lineWidth = 1
NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.93, alpha: 1).setStroke(); border.stroke()

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

draw("安装 PCL.Mac", rect: NSRect(x: 60, y: 420, width: 340, height: 36), font: .systemFont(ofSize: 30, weight: .bold), color: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1))
draw("将左侧应用拖到右侧“应用程序”文件夹", rect: NSRect(x: 60, y: 382, width: 580, height: 28), font: .systemFont(ofSize: 18, weight: .semibold), color: NSColor(calibratedRed: 0.28, green: 0.35, blue: 0.45, alpha: 1))
draw("安装完成后，请从“应用程序”中启动。\n如果系统有安全提示，请在“应用程序”里再次打开一次。", rect: NSRect(x: 60, y: 332, width: 520, height: 44), font: .systemFont(ofSize: 14, weight: .regular), color: NSColor(calibratedRed: 0.45, green: 0.50, blue: 0.58, alpha: 1))
draw("拖动安装", rect: NSRect(x: 125, y: 135, width: 120, height: 22), font: .systemFont(ofSize: 17, weight: .semibold), color: NSColor(calibratedRed: 0.27, green: 0.34, blue: 0.42, alpha: 1), alignment: .center)
draw("Applications", rect: NSRect(x: 560, y: 135, width: 160, height: 22), font: .systemFont(ofSize: 17, weight: .semibold), color: NSColor(calibratedRed: 0.27, green: 0.34, blue: 0.42, alpha: 1), alignment: .center)

let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 280, y: 252))
arrow.line(to: CGPoint(x: 520, y: 252))
arrow.lineWidth = 8
arrow.lineCapStyle = .round
NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.95, alpha: 1).setStroke(); arrow.stroke()
let head = NSBezierPath()
head.move(to: CGPoint(x: 520, y: 252))
head.line(to: CGPoint(x: 485, y: 278))
head.line(to: CGPoint(x: 485, y: 226))
head.close()
NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.95, alpha: 1).setFill(); head.fill()

draw("PCL.Mac Installer", rect: NSRect(x: 60, y: 54, width: 220, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.68, alpha: 1))

ctx.setStrokeColor(NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.95, alpha: 1).cgColor)
ctx.setLineWidth(1)
ctx.stroke(CGRect(x: 26, y: 26, width: 748, height: 468))

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
    tell disk "PCL.Mac"
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
        delay 2
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

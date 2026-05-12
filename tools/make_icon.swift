#!/usr/bin/env swift
//
//  Generates a basic 1024×1024 BudgetBot app icon. Run from repo root:
//
//      swift tools/make_icon.swift
//
//  Drops `Icon-1024.png` into the AppIcon asset catalog.
//
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo
) else { fatalError("CGContext") }

// Gradient background — BudgetBot green
let colors: [CGColor] = [
    CGColor(red: 0.13, green: 0.74, blue: 0.44, alpha: 1.0),
    CGColor(red: 0.05, green: 0.40, blue: 0.28, alpha: 1.0)
]
let stops: [CGFloat] = [0.0, 1.0]
let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: stops)!
ctx.drawLinearGradient(
    gradient,
    start: .zero,
    end: CGPoint(x: 0, y: CGFloat(size)),
    options: []
)

// Soft inner glow circle
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
let glowRect = CGRect(x: 120, y: 180, width: 784, height: 784)
ctx.fillEllipse(in: glowRect)

// Big "$" centered
let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 720, nil)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let attrs: [CFString: Any] = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: white
]
let astr = CFAttributedStringCreate(nil, "$" as CFString, attrs as CFDictionary)!
let line = CTLineCreateWithAttributedString(astr)

var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
let textHeight = ascent + descent

let originX = (CGFloat(size) - CGFloat(width)) / 2
// CG y-up coordinate system: place baseline so glyph is visually centered
let originY = (CGFloat(size) - textHeight) / 2 + descent * 0.4

ctx.textPosition = CGPoint(x: originX, y: originY)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage() else { fatalError("makeImage") }

let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("BudgetBot/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png")

guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL,
    UTType.png.identifier as CFString,
    1, nil
) else { fatalError("dest") }

CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("finalize") }
print("wrote \(outURL.path)")

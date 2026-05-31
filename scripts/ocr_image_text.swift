#!/usr/bin/env swift
import AppKit
import Foundation
import Vision

struct OcrLine: Encodable {
    let index: Int
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = CommandLine.arguments.dropFirst()
guard let imagePath = args.first else {
    fail("Usage: scripts/ocr_image_text.swift /path/to/image.png", code: 2)
}

guard let image = NSImage(contentsOfFile: imagePath) else {
    fail("Could not open image: \(imagePath)")
}

var rect = CGRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
    fail("Could not convert image to CGImage: \(imagePath)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = ["zh-Hans", "en-US"]

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    fail("OCR failed: \(error)")
}

let observations = request.results ?? []
let lines: [OcrLine] = observations.enumerated().compactMap { index, observation in
    guard let candidate = observation.topCandidates(1).first else {
        return nil
    }
    let box = observation.boundingBox
    return OcrLine(
        index: index,
        text: candidate.string,
        confidence: candidate.confidence,
        x: box.origin.x,
        y: box.origin.y,
        width: box.size.width,
        height: box.size.height
    )
}

do {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(lines)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fail("Could not encode OCR result: \(error)")
}

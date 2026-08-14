//
//  GarmentClassifierService.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 11/08/26.
//

//
//import CoreML
//import Vision
//
//final class GarmentClassifierService {
//
//    func classifyGarment(cropped cgImage: CGImage) throws -> [VNClassificationObservation] {
//        let model = try VNCoreMLModel(for: GarmentClassifier().model) // your trained model, once it exists
//        let request = VNCoreMLRequest(model: model)
//        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
//        try handler.perform([request])
//        return (request.results as? [VNClassificationObservation]) ?? []
//    }
//}

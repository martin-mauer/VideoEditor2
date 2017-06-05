//
//  CompositionDebugView.swift
//  VideoEditor
//
//  Created by Mobdev125 on 6/3/17.
//  Copyright © 2017 Mobdev125. All rights reserved.
//

import UIKit
import CoreMedia
import AVFoundation

class CompositionTrackSegmentInfo: NSObject {
    var timeRange: CMTimeRange?
    var empty: Bool?
    var mediaType: String?
    var descriptionString: String?
}

class VideoCompositionStageInfo: NSObject {
    var timeRange: CMTimeRange?
    var layerNames: [String]?
    var opacityRamps: [String: [NSValue]]?
}
class CompositionDebugView: UIView {
    
    let kLeftInset:CGFloat = 66
    let kRightInset:CGFloat = 90
    let kLeftmarginInset:CGFloat = 4

    let kBannerHeight:CGFloat = 20
    let kIdealRowHeight:CGFloat = 36
    let kGapAfterRows:CGFloat = 4

    fileprivate var drawingLayer: CALayer?
    fileprivate var duration: CMTime?
    fileprivate var compositionRectWidth: CGFloat?
    
    fileprivate var compositionTracks: [[CompositionTrackSegmentInfo]]?
    fileprivate var audioMixTracks: [[NSValue]]?
    fileprivate var videoCompositionStages: [VideoCompositionStageInfo]?
    
    fileprivate var scaledDurationToWidth: CGFloat?
    
    var player: AVPlayer?
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        drawingLayer = self.layer
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    // Value harversting
    func synchronizeToComposition(_ composition: AVComposition?, videoComposition: AVVideoComposition?, audioMix: AVAudioMix?) {
        compositionTracks = nil
        audioMixTracks = nil
        videoCompositionStages = nil
        
        duration = CMTimeMake(1, 1)
        if composition != nil {
            var tracks = [[CompositionTrackSegmentInfo]]()
            for t in composition!.tracks {
                var segments = [CompositionTrackSegmentInfo]()
                for s in t.segments {
                    let segment = CompositionTrackSegmentInfo()
                    if s.isEmpty {
                        segment.timeRange = s.timeMapping.target
                    }
                    else {
                        segment.timeRange = s.timeMapping.source
                    }
                    
                    segment.empty = s.isEmpty
                    segment.mediaType = t.mediaType
                    if !segment.empty! {
                        var desc:String = ""
                        desc = desc.appendingFormat("%1.1f - %1.1f: \"%@\" ", CMTimeGetSeconds((segment.timeRange?.start)!), CMTimeGetSeconds(CMTimeRangeGetEnd(segment.timeRange!)), (s.sourceURL?.lastPathComponent)!)
                        if segment.mediaType == AVMediaTypeAudio {
                            desc.append("(a)")
                        }
                        else if segment.mediaType == AVMediaTypeVideo {
                            desc.append("(v)")
                        }
                        else {
                            desc = desc.appendingFormat("('%@')", segment.mediaType!)
                        }
                        segment.descriptionString = desc
                    }
                    segments.append(segment)
                }
                
                tracks.append(segments)
            }
            
            compositionTracks = tracks
            duration = CMTimeMaximum(duration!, (composition?.duration)!)
        }
        
        if audioMix != nil {
            var mixTracks = [[NSValue]]()
            for input in audioMix!.inputParameters {
                var ramp = [NSValue]()
                var startTime = kCMTimeZero
                var startVolume:Float = 1.0
                var endVolumne:Float = 1.0
                var timeRange: CMTimeRange = CMTimeRange()
                
                while input.getVolumeRamp(for: startTime, startVolume: &startVolume, endVolume: &endVolumne, timeRange: &timeRange) {
                    if startTime == kCMTimeZero && timeRange.start == kCMTimeZero {
                        ramp.append(NSValue(cgPoint: CGPoint(x: 0.0, y: 1.0)))
                        ramp.append(NSValue(cgPoint: CGPoint(x: CMTimeGetSeconds(timeRange.start), y: 1.0)))
                    }
                    ramp.append(NSValue(cgPoint: CGPoint(x: CMTimeGetSeconds(timeRange.start), y: Float64(startVolume))))
                    ramp.append(NSValue(cgPoint: CGPoint(x: CMTimeGetSeconds(CMTimeRangeGetEnd(timeRange)), y: Float64(endVolumne))))
                    
                    startTime = CMTimeRangeGetEnd(timeRange)
                }
                if startTime < duration! {
                    ramp.append(NSValue(cgPoint: CGPoint(x: CMTimeGetSeconds(duration!), y: Float64(endVolumne))))
                }
                
                mixTracks.append(ramp)
            }
            audioMixTracks = mixTracks
        }
        
        if videoComposition != nil {
            var stages = [VideoCompositionStageInfo]()
            for instruction in videoComposition!.instructions {
                let stage = VideoCompositionStageInfo()
                stage.timeRange = instruction.timeRange
                var rampsDictionary = [String: [NSValue]]()
                
                if instruction is AVVideoCompositionInstruction {
                    let instruction: AVVideoCompositionInstruction = instruction as! AVVideoCompositionInstruction
                    var layerNames = [String]()
                    for layerInstruction in instruction.layerInstructions {
                        var ramp = [NSValue]()
                        var startTime = kCMTimeZero
                        var startOpacity: Float = 1.0
                        var endOpacity: Float = 1.0
                        var timeRange: CMTimeRange = CMTimeRange()
                        
                        while layerInstruction.getOpacityRamp(for: startTime, startOpacity: &startOpacity, endOpacity: &endOpacity, timeRange: &timeRange) {
                            if startTime == kCMTimeZero && timeRange.start > kCMTimeZero {
                                ramp.append(NSValue(cgPoint: CGPoint(x: CMTimeGetSeconds(timeRange.start), y: Float64(startOpacity))))
                            }
                            ramp.append(NSValue(cgPoint: CGPoint(x: CMTimeGetSeconds(CMTimeRangeGetEnd(timeRange)), y: Float64(endOpacity))))
                            startTime = CMTimeRangeGetEnd(timeRange)
                        }
                        
                        let name = "\(layerInstruction.trackID)"
                        layerNames.append(name)
                        rampsDictionary[name] = ramp
                    }
                    
                    if layerNames.count > 1 {
                        stage.opacityRamps = rampsDictionary
                    }
                    
                    stage.layerNames = layerNames
                    stages.append(stage)
                }
            }
            videoCompositionStages = stages
        }
        
        drawingLayer?.setNeedsDisplay()
    }
    
    // View drawing
    override func willMove(toSuperview newSuperview: UIView?) {
        drawingLayer?.frame = self.bounds
        drawingLayer?.delegate = self
        drawingLayer?.setNeedsDisplay()
    }
    
    override func removeFromSuperview() {
        drawingLayer?.delegate = nil
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        let rect = rect.insetBy(dx: kLeftmarginInset, dy: 4.0)
        
        let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        style.alignment = .center
        let textAttributes = [NSForegroundColorAttributeName: UIColor.white, NSParagraphStyleAttributeName: style] as [String : Any]
        
        let numBanners = (compositionTracks != nil ? 1:0) + (audioMixTracks != nil ? 1:0) + (videoCompositionStages != nil ? 1:0)
        let numRows = (compositionTracks == nil ? 0:compositionTracks?.count)! + (audioMixTracks == nil ? 0:audioMixTracks?.count)! + (videoCompositionStages != nil ? 1:0)
        let totalBannerHeight = CGFloat(numBanners) * (kBannerHeight + kGapAfterRows)
        var rowHeight = kIdealRowHeight
        if numRows > 0 {
            let maxRowHeight = (rect.size.height - totalBannerHeight) / CGFloat(numRows)
            rowHeight = min(rowHeight, maxRowHeight)
        }
        var runningTop = rect.origin.y
        var bannerRect = rect
        bannerRect.size.height = kBannerHeight
        bannerRect.origin.y = runningTop
        
        var rowRect = rect
        rowRect.size.height = rowHeight
        
        rowRect.origin.x = rowRect.origin.x + kLeftInset
        rowRect.size.width = rowRect.size.width - (kLeftInset + kRightInset)
        compositionRectWidth = rowRect.size.width
        
        scaledDurationToWidth = compositionRectWidth! / CGFloat(duration == nil ? 1.0: CMTimeGetSeconds(duration!))
        
        if compositionTracks != nil {
            bannerRect.origin.y = runningTop
            context?.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            NSString(format: "AVComposition").draw(in: bannerRect, withAttributes: [NSForegroundColorAttributeName: UIColor.white])
            
            runningTop = runningTop + bannerRect.size.height
            for track in compositionTracks! {
                rowRect.origin.y = runningTop
                var segmentRect = rowRect
                for segment in track {
                    segmentRect.size.width = CGFloat(CMTimeGetSeconds((segment.timeRange?.duration)!)) * scaledDurationToWidth!
                    
                    if segment.empty! {
                        context?.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
                    }
                    else {
                        if segment.mediaType == AVMediaTypeVideo {
                            context?.setFillColor(red: 0.0, green: 0.36, blue: 036, alpha: 1.0)
                            context?.setStrokeColor(red: 0.0, green: 0.5, blue: 0.5, alpha: 1.0)
                        }
                        else {
                            context?.setFillColor(red: 0.0, green: 0.24, blue: 036, alpha: 1.0)
                            context?.setStrokeColor(red: 0.0, green: 0.33, blue: 0.6, alpha: 1.0)
                        }
                        context?.setLineWidth(2.0)
                        context?.addRect(segmentRect.insetBy(dx: 3.0, dy: 3.0))
                        context?.drawPath(using: CGPathDrawingMode.fillStroke)
                        
                        context?.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
                        segment.descriptionString?.drawVerticallyCenteredInRect(rect: segmentRect, withAttributes: textAttributes)
                    }
                    
                    segmentRect.origin.x = segmentRect.origin.x + segmentRect.size.width
                }
                
                runningTop = runningTop + rowRect.size.height
            }
            runningTop = runningTop + kGapAfterRows
        }
        
        if videoCompositionStages != nil {
            bannerRect.origin.y = runningTop
            context?.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            NSString(format: "AVVideoComposition").draw(in: bannerRect, withAttributes: [NSForegroundColorAttributeName: UIColor.white])
            runningTop = runningTop + bannerRect.size.height
            
            rowRect.origin.y = runningTop
            var stageRect = rowRect
            for stage in videoCompositionStages! {
                stageRect.size.width = CGFloat(CMTimeGetSeconds((stage.timeRange?.duration)!)) * scaledDurationToWidth!
                let layerCount = stage.layerNames?.count
                var layerRect = stageRect
                if layerCount! > 0 {
                    layerRect.size.height = layerRect.size.height / CGFloat(layerCount!)
                }
                
                for layerName in stage.layerNames! {
                    if (layerName as NSString).intValue % 2 == 1 {
                        context?.setFillColor(red: 0.55, green: 0.02, blue: 0.02, alpha: 1.00)
                        context?.setStrokeColor(red: 0.87, green: 0.10, blue: 0.10, alpha: 1.0)
                    }
                    else {
                        context?.setFillColor(red: 0.00, green: 0.40, blue: 0.76, alpha: 1.00)
                        context?.setStrokeColor(red: 0.00, green: 0.67, blue: 1.00, alpha: 1.0)
                    }
                    
                    context?.setLineWidth(2.0)
                    context?.addRect(layerRect.insetBy(dx: 3.0, dy: 1.0))
                    context?.drawPath(using: .fillStroke)
                    
                    context?.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
                    layerName.drawVerticallyCenteredInRect(rect: layerRect, withAttributes: textAttributes)
                    let rampArray = stage.opacityRamps?[layerName]
                    if rampArray != nil && (rampArray?.count)! > 0 {
                        var rampRect = layerRect
                        rampRect.size.width = CGFloat(CMTimeGetSeconds(duration!)) * scaledDurationToWidth!
                        rampRect = rampRect.insetBy(dx: 3.0, dy: 3.0)
                        
                        context?.beginPath()
                        context?.setStrokeColor(red: 0.95, green: 0.68, blue: 0.09, alpha: 1.0)
                        context?.setLineWidth(2.0)
                        
                        var firstPoint = true
                        
                        for pointValue in rampArray! {
                            let timeVolumePoint = pointValue.cgPointValue
                            var pointInRow: CGPoint = CGPoint()
                            pointInRow.x = CGFloat(self.horizontalPositionForTime(CMTimeMakeWithSeconds(Float64(timeVolumePoint.x), 1)) - 3.0)
                            pointInRow.y = rampRect.origin.y + (0.9 - 0.8 * timeVolumePoint.y) * rampRect.size.height
                            
                            pointInRow.x = max(pointInRow.x, rampRect.minX)
                            pointInRow.x = min(pointInRow.x, rampRect.maxX)
                            
                            if firstPoint {
                                context?.move(to: pointInRow)
                                firstPoint = false
                            }
                            else {
                                context?.addLine(to: pointInRow)
                            }
                        }
                        context?.strokePath()
                    }
                    layerRect.origin.y = layerRect.origin.y + layerRect.size.height
                }
                
                stageRect.origin.x = stageRect.origin.x + stageRect.size.width
            }
            
            runningTop = runningTop + rowRect.size.height
            runningTop = runningTop + kGapAfterRows
        }
        
        if audioMixTracks != nil {
            bannerRect.origin.y = runningTop
            context?.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            NSString(format: "AVAudioMix").draw(in: bannerRect, withAttributes: [NSForegroundColorAttributeName: UIColor.white])
            runningTop = runningTop + bannerRect.size.height
            
            for mixTrack in audioMixTracks! {
                rowRect.origin.y = runningTop
                var rampRect = rowRect
                rampRect.size.width = CGFloat(CMTimeGetSeconds(duration!)) * scaledDurationToWidth!
                rampRect = rampRect.insetBy(dx: 3.0, dy: 3.0)
                
                context?.setFillColor(red: 0.56, green: 0.02, blue: 0.02, alpha: 1.00)
                context?.setStrokeColor(red: 0.87, green: 0.10, blue: 0.10, alpha: 1.00)
                context?.setLineWidth(2.0)
                context?.addRect(rampRect)
                context?.drawPath(using: .fillStroke)
                
                context?.beginPath()
                context?.setStrokeColor(red: 0.95, green: 0.68, blue: 0.09, alpha: 1.00)
                context?.setLineWidth(3.0)
                
                var firstPoint = true
                for pointValue in mixTrack {
                    let timeVolumePoint = pointValue.cgPointValue
                    var pointInRow = CGPoint()
                    pointInRow.x = rampRect.origin.x + timeVolumePoint.x * scaledDurationToWidth!
                    pointInRow.y = rampRect.origin.y + (0.9 - 0.8 * timeVolumePoint.y) * rampRect.size.height
                    
                    pointInRow.x = max(pointInRow.x, rampRect.minX)
                    pointInRow.x = min(pointInRow.x, rampRect.maxX)
                    
                    if firstPoint {
                        context?.move(to: pointInRow)
                        firstPoint = false
                    }
                    else {
                        context?.addLine(to: pointInRow)
                    }
                }
                context?.strokePath()
                runningTop = runningTop + rowRect.size.height
            }
            runningTop = runningTop + kGapAfterRows
        }
        
        if compositionTracks != nil {
            self.layer.sublayers = nil
            let visibleRect = self.layer.bounds
            var currentTimeRect = visibleRect
            
            currentTimeRect.origin.x = 0
            currentTimeRect.size.width = 8
            
            let timeMarkerRedBandLayer = CAShapeLayer()
            timeMarkerRedBandLayer.frame = currentTimeRect
            timeMarkerRedBandLayer.position = CGPoint(x: rowRect.origin.x, y: self.bounds.size.height / 2)
            let linePath = CGPath(rect: currentTimeRect, transform: nil)
            timeMarkerRedBandLayer.fillColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5).cgColor
            timeMarkerRedBandLayer.path = linePath
            
            currentTimeRect.origin.x = 0
            currentTimeRect.size.width = 1
            
            let timeMarkerWhiteLineLayer = CAShapeLayer()
            timeMarkerWhiteLineLayer.frame = currentTimeRect
            timeMarkerWhiteLineLayer.position = CGPoint(x: 4, y: self.bounds.size.height / 2)
            let whiteLinePath = CGPath(rect: currentTimeRect, transform: nil)
            timeMarkerWhiteLineLayer.fillColor =  UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0).cgColor
            timeMarkerWhiteLineLayer.path = whiteLinePath
            
            timeMarkerRedBandLayer.addSublayer(timeMarkerWhiteLineLayer)
            
            let scrubbingAnimation = CABasicAnimation(keyPath: "position.x")
            scrubbingAnimation.fromValue = NSNumber(value: self.horizontalPositionForTime(kCMTimeZero))
            scrubbingAnimation.toValue = NSNumber(value: self.horizontalPositionForTime(duration!))
            scrubbingAnimation.isRemovedOnCompletion = false
            scrubbingAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            scrubbingAnimation.duration = CMTimeGetSeconds(duration!)
            scrubbingAnimation.fillMode = kCAFillModeBoth
            timeMarkerRedBandLayer.add(scrubbingAnimation, forKey: nil)
            
            if self.player?.currentItem != nil {
                let synclayer = AVSynchronizedLayer(playerItem: (self.player?.currentItem!)!)
                synclayer.addSublayer(timeMarkerRedBandLayer)
                self.layer.addSublayer(synclayer)
            }
        }
    }
    
    func horizontalPositionForTime(_ time: CMTime) -> Double {
        var seconds = 0.0
        if CMTIME_IS_NUMERIC(time) && time > kCMTimeZero {
            seconds = CMTimeGetSeconds(time)
        }
        return seconds * Double(scaledDurationToWidth!) + Double(kLeftInset) + Double(kLeftmarginInset)
    }
}

extension String {
    func drawVerticallyCenteredInRect(rect: CGRect, withAttributes attributes: [String: Any]) {
        let size = (self as NSString).size(attributes: attributes)
        var rect = rect
        rect.origin.y = rect.origin.y + (rect.size.height - size.height) / 2.0
        (self as NSString).draw(in: rect, withAttributes: attributes)
    }
}

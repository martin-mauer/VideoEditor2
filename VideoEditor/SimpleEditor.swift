//
//  SimpleEditor.swift
//  VideoEditor
//
//  Created by Mobdev125 on 6/3/17.
//  Copyright © 2017 Mobdev125. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation

class SimpleEditor: NSObject {
    var clips: [AVURLAsset]?
    var clipTimeRanges: [CMTimeRange]?
    var transitionDuration: CMTime?
    var composition: AVMutableComposition?
    var videoComposition: AVMutableVideoComposition?
    var audioMix: AVMutableAudioMix?
    
    func buildTransitionComposition(_ composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix) {
        
        var nextClipStartTime = kCMTimeZero
        let clipsCount = self.clips?.count
        var transitionDuration = self.transitionDuration
        for clipTimeRange in self.clipTimeRanges! {
            var halfClipDuration = clipTimeRange.duration
            halfClipDuration.timescale = halfClipDuration.timescale * 2
            transitionDuration = CMTimeMinimum(transitionDuration!, halfClipDuration)
        }
        
        var compositionVideoTracks = [composition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid),
                                      composition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)]
        var compositionAudioTracks = [composition.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid),
                                      composition.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)]
        
        let passThroughTimeRanges = UnsafeMutablePointer<CMTimeRange>.allocate(capacity: MemoryLayout<CMTimeRange>.size * clipsCount!)
        let transitionTimeRanges = UnsafeMutablePointer<CMTimeRange>.allocate(capacity: MemoryLayout<CMTimeRange>.size * clipsCount!)
        
        for i in 0..<clipsCount! {
            let alternatingIndex = i % 2
            let asset = self.clips![i]
            var timeRangeInAsset: CMTimeRange
            if self.clipTimeRanges!.count > i {
                let clipTimeRange = self.clipTimeRanges![i]
                timeRangeInAsset = clipTimeRange
            }
            else {
                timeRangeInAsset = CMTimeRangeMake(kCMTimeZero, asset.duration)
            }
            
            let clipVideoTrack = asset.tracks(withMediaType: AVMediaTypeVideo)[0]
            try! compositionVideoTracks[alternatingIndex].insertTimeRange(timeRangeInAsset, of: clipVideoTrack, at: nextClipStartTime)
            
            let clipAudioTrack = asset.tracks(withMediaType: AVMediaTypeAudio)[0]
            try! compositionAudioTracks[alternatingIndex].insertTimeRange(timeRangeInAsset, of: clipAudioTrack, at: nextClipStartTime)
            
            passThroughTimeRanges[i] = CMTimeRangeMake(nextClipStartTime, timeRangeInAsset.duration)
            if i > 0 {
                passThroughTimeRanges[i].start = CMTimeAdd(passThroughTimeRanges[i].start, transitionDuration!)
                passThroughTimeRanges[i].duration = CMTimeSubtract(passThroughTimeRanges[i].duration, transitionDuration!)
            }
            
            if i+1 < clipsCount! {
                passThroughTimeRanges[i].duration = CMTimeSubtract(passThroughTimeRanges[i].duration, transitionDuration!)
            }
            
            nextClipStartTime = CMTimeAdd(nextClipStartTime, timeRangeInAsset.duration)
            nextClipStartTime = CMTimeSubtract(nextClipStartTime, transitionDuration!)
            
            if i+1 < clipsCount! {
                transitionTimeRanges[i] = CMTimeRangeMake(nextClipStartTime, transitionDuration!)
            }
        }
        
        var instructions = [AVMutableVideoCompositionInstruction]()
        var trackMixArray = [AVMutableAudioMixInputParameters]()
        
        for i in 0..<clipsCount! {
            let alternatingIndex = i % 2
            let passThroughInstruction = AVMutableVideoCompositionInstruction()
            passThroughInstruction.timeRange = passThroughTimeRanges[i]
            let passThroughlayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTracks[alternatingIndex])
            
            passThroughInstruction.layerInstructions = [passThroughlayer]
            instructions.append(passThroughInstruction)
            
            if i+1 < clipsCount! {
                let transitionInstruction = AVMutableVideoCompositionInstruction()
                transitionInstruction.timeRange = transitionTimeRanges[i]
                let fromLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTracks[alternatingIndex])
                let toLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTracks[1 - alternatingIndex])
                toLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: transitionTimeRanges[i])
                transitionInstruction.layerInstructions = [toLayer, fromLayer]
                instructions.append(transitionInstruction)
                
                let trackMix1 = AVMutableAudioMixInputParameters(track: compositionAudioTracks[0])
                trackMix1.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: transitionTimeRanges[0])
                trackMixArray.append(trackMix1)
                
                let trackMix2 = AVMutableAudioMixInputParameters(track: compositionAudioTracks[1])
                trackMix2.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: transitionTimeRanges[0])
                trackMix2.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 1.0, timeRange: passThroughTimeRanges[1])
                trackMixArray.append(trackMix2)
            }
        }
        audioMix.inputParameters = trackMixArray
        videoComposition.instructions = instructions
    }
    
    func buildCompositionObjectsForPlayback() {
        if self.clips == nil || self.clips?.count == 0 {
            self.composition = nil
            self.videoComposition = nil
            
            return
        }
        
        let videoSize = (self.clips![0]).tracks(withMediaType: AVMediaTypeVideo)[0].naturalSize
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        let audioMix = AVMutableAudioMix()
        
        composition.naturalSize = videoSize
        
        self.buildTransitionComposition(composition, videoComposition: videoComposition, audioMix: audioMix)
        
        videoComposition.frameDuration = CMTimeMake(1, 30)
        videoComposition.renderSize = videoSize
        
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
    }
    
    func playerItem() -> AVPlayerItem? {
        let playerItem = AVPlayerItem(asset: self.composition!)
        playerItem.videoComposition = self.videoComposition
        playerItem.audioMix = self.audioMix
        return playerItem
    }
}



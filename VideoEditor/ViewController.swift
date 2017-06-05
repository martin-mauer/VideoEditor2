//
//  ViewController.swift
//  VideoEditor
//
//  Created by Mobdev125 on 6/2/17.
//  Copyright © 2017 Mobdev125. All rights reserved.
//

import UIKit
import CoreMedia
import Photos
import MobileCoreServices

class ViewController: UIViewController {
    
    var AVCDVPlayerViewControllerStatusObservationContext = "AVCDVPlayerViewControllerStatusObservationContext"
    var AVCDVPlayerViewControllerRateObservationContext = "AVCDVPlayerViewControllerRateObservationContext"
    
    fileprivate var mPlaying: Bool? = false
    fileprivate var mScrubInFlight: Bool? = false
    fileprivate var mSeekToZeroBeforPlaying: Bool? = true
    fileprivate var mLastScrubSliderValue:Float?
    fileprivate var mPlayRateToRestore: Float?
    fileprivate var mTimeObserver: Any?
    fileprivate var mTransitionDuration: Float?
    fileprivate var mTransitionsEnabled: Bool?
    
    var editor: SimpleEditor?
    var clips: [AVURLAsset]?
    var clipTimeRanges: [CMTimeRange]?
    var player: AVPlayer?
    var playerItem: AVPlayerItem?
    
    @IBOutlet weak var playerView: PlayerView!
    @IBOutlet weak var compositionDebugView: CompositionDebugView!
    @IBOutlet weak var scrubber: UISlider!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var currentTimeLabel: UILabel!
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.editor = SimpleEditor()
        self.clips = [AVURLAsset]()
        self.clipTimeRanges = [CMTimeRange]()
        
        // Defaults for the transition settings.
        self.mTransitionDuration = 2.0
        self.mTransitionsEnabled = true
        
        // Add the clips from the main bundle to create a composition using them
        self.setupEditingAndPlayBack()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.player == nil {
            self.mSeekToZeroBeforPlaying = false
            self.player = AVPlayer()
            self.player?.addObserver(self, forKeyPath: "rate", options: NSKeyValueObservingOptions(rawValue: NSKeyValueObservingOptions.old.rawValue | NSKeyValueObservingOptions.new.rawValue), context: &AVCDVPlayerViewControllerRateObservationContext)
            self.playerView.player = self.player!
        }
        
        self.addTimeObserverToPlayer()
        
        // Build AVComposition and AVVideoComposition objects for playback
        self.editor?.buildCompositionObjectsForPlayback()
        self.synchronizedWithEditor()
        
        // Set AVPlayer and all composition objects on the AVCompositionDebugView
        self.compositionDebugView.player = self.player
        self.compositionDebugView.synchronizeToComposition((self.editor?.composition)!, videoComposition: (self.editor?.videoComposition)!, audioMix: (self.editor?.audioMix)!)
        self.compositionDebugView.setNeedsDisplay()
        
        self.updateScrubber()
        self.updateTimeLabel()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.player?.pause()
        self.removeTimeObserverFromPlayer()
    }
    
    // Simple Editor
    
    func setupEditingAndPlayBack() {
        let asset1 = AVURLAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "sample_clip1", ofType: "m4v")!))
        let asset2 = AVURLAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "sample_clip2", ofType: "mov")!))
        
        let dispatchGroup = DispatchGroup()
        let assetKeysToLoadAndTest = ["tracks", "duration", "composable"]
        
        self.loadAsset(asset1, withKeys: assetKeysToLoadAndTest, usingDispatchGroup: dispatchGroup)
        self.loadAsset(asset2, withKeys: assetKeysToLoadAndTest, usingDispatchGroup: dispatchGroup)
        
        // wait until both assets are loaded
        dispatchGroup.notify(queue: .main) { 
            self.synchronizedWithEditor()
        }
    }
    
    func loadAsset(_ asset: AVURLAsset, withKeys assetKeysToLoad: [String], usingDispatchGroup dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        asset.loadValuesAsynchronously(forKeys: assetKeysToLoad) {
            for key in assetKeysToLoad {
                var error: NSError? = nil
                if asset.statusOfValue(forKey: key, error: &error) == AVKeyValueStatus.failed {
                    print("Key value loading failed for key\(key) with error: \(error!)")
                    dispatchGroup.leave()
                    return
                }
            }
            
            if !asset.isComposable {
                print("Asset is not composable")
                dispatchGroup.leave()
                return
            }
            
            self.clips?.append(asset)
            self.clipTimeRanges?.append(CMTimeRangeMake(CMTimeMakeWithSeconds(0, 1), CMTimeMakeWithSeconds(5, 1)))
            
            dispatchGroup.leave()
        }
    }
    
    func synchronizedWithEditor() {
        self.synchronizeEditorClipsWithOurClips()
        self.synchronizeEditorClipTimeRangesWithOurClipTimeRanges()
        
        if self.mTransitionsEnabled! {
            self.editor?.transitionDuration = CMTimeMakeWithSeconds(Float64(self.mTransitionDuration!), 600)
        }
        else {
            self.editor?.transitionDuration = kCMTimeInvalid
        }
        
        self.editor?.buildCompositionObjectsForPlayback()
        self.synchronizePlayerWithEditor()
        
        self.compositionDebugView.player = self.player
        self.compositionDebugView.synchronizeToComposition((self.editor?.composition)!, videoComposition: (self.editor?.videoComposition)!, audioMix: (self.editor?.audioMix)!)
        self.compositionDebugView.setNeedsDisplay()
    }
    
    func synchronizePlayerWithEditor() {
        if self.player == nil {
            return
        }
        
        let playerItem = self.editor?.playerItem()
        if self.playerItem != playerItem {
            if self.playerItem != nil {
                self.playerItem?.removeObserver(self, forKeyPath: "status")
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.playerItem)
            }
            
            self.playerItem = playerItem
            
            if self.playerItem != nil {
                self.playerItem?.addObserver(self, forKeyPath: "status", options: (NSKeyValueObservingOptions(rawValue: NSKeyValueObservingOptions.new.rawValue | NSKeyValueObservingOptions.initial.rawValue)), context: &AVCDVPlayerViewControllerStatusObservationContext)
                NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.playerItem)
            }
            self.player?.replaceCurrentItem(with: playerItem)
        }
    }
    
    func synchronizeEditorClipsWithOurClips() {
//        var validClips = [AVURLAsset]()
//        for asset in self.clips! {
//            if asset != nil {
//                validClips.append(asset)
//            }
//        }
        
        self.editor?.clips = self.clips
    }
    
    func synchronizeEditorClipTimeRangesWithOurClipTimeRanges() {
//        var validClipTimeRanges = [NSValue]()
//        for timeRange in self.clipTimeRanges! {
//            if timeRange != nil {
//                validClipTimeRanges.append(timeRange as NSValue)
//            }
//        }
        self.editor?.clipTimeRanges = self.clipTimeRanges //validClipTimeRanges as? [CMTimeRange]
    }
    
    
    // Utilities
    
    func addTimeObserverToPlayer() {
        if self.mTimeObserver != nil {
            return
        }
        
        if self.player == nil {
            return
        }
        
        if self.player?.currentItem?.status != AVPlayerItemStatus.readyToPlay {
            return
        }
        
        let duration = CMTimeGetSeconds(self.playerItemDuration())
        
        if __inline_isfinited(duration) != 0 {
            let width = self.scrubber.bounds.width
            var interval = 0.5 * duration / Double(width)
            
            if interval > 1.0 {
                interval = 1.0
            }
            
            weak var weakSelf = self
            self.mTimeObserver = self.player?.addPeriodicTimeObserver(forInterval:  CMTimeMakeWithSeconds(interval, Int32(NSEC_PER_SEC)), queue: DispatchQueue.main, using: { (time) in
                weakSelf?.updateScrubber()
                weakSelf?.updateTimeLabel()
            })
        }
    }
    
    func removeTimeObserverFromPlayer() {
        if self.mTimeObserver != nil {
            self.player?.removeTimeObserver(self.mTimeObserver!)
            self.mTimeObserver = nil
        }
    }
    
    func playerItemDuration() -> CMTime {
        let playerItem = self.player?.currentItem
        var itemDuration = kCMTimeInvalid
        if playerItem?.status == AVPlayerItemStatus.readyToPlay {
            itemDuration = (playerItem?.duration)!
        }
        
        return itemDuration
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &AVCDVPlayerViewControllerRateObservationContext {
            let newRate = (change?[NSKeyValueChangeKey.newKey] as! NSNumber).floatValue
            let oldRateNum = change?[NSKeyValueChangeKey.oldKey]
            if oldRateNum is NSNumber && newRate != (oldRateNum as! NSNumber).floatValue {
                self.mPlaying = newRate != 0.0 || self.mPlayRateToRestore != 0.0
                self.updatePlayPauseButton()
                self.updateScrubber()
                self.updateTimeLabel()
            }
        }
        else if context == &AVCDVPlayerViewControllerStatusObservationContext {
            let playerItem = object as? AVPlayerItem
            if playerItem?.status == AVPlayerItemStatus.readyToPlay {
                self.addTimeObserverToPlayer()
            }
            else if playerItem?.status == AVPlayerItemStatus.failed {
                self.reportError((playerItem?.error)!)
            }
        }
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    func updatePlayPauseButton() {
        self.playPauseButton.isSelected = self.mPlaying! ? true:false
        self.playPauseButton.setNeedsDisplay()
    }
    
    func updateTimeLabel() {
        var seconds = CMTimeGetSeconds((self.player?.currentTime())!)
        if __inline_isfinited(seconds) == 0 {
            seconds = 0
        }
        var secondsInt = Int(round(seconds))
        let minutes = Int(secondsInt / 60)
        secondsInt = secondsInt - minutes * 60
        
        self.currentTimeLabel.textColor = UIColor(white: 1.0, alpha: 1.0)
        self.currentTimeLabel.textAlignment = .center
        self.currentTimeLabel.text = String(format: "%.2i:%.2i", minutes, secondsInt)
    }
    
    func updateScrubber() {
        let duration = CMTimeGetSeconds(self.playerItemDuration())
        if __inline_isfinited(duration) != 0 {
            let time = CMTimeGetSeconds((self.player?.currentTime())!)
            self.scrubber.setValue(Float(time / duration), animated: true)
        }
        else {
            self.scrubber.setValue(0.0, animated: false)
        }
    }
    
    func reportError(_ error: Error) {
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: error.localizedDescription, message: error.localizedDescription, preferredStyle: .alert)
                let actionButton = UIAlertAction(title: "OK", style: .default, handler: nil)
                alert.addAction(actionButton)
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    // IBActions
    
    @IBAction func togglePlayPause(_ sender: Any?) {
        self.mPlaying = !self.mPlaying!
        if self.mPlaying! {
            if self.mSeekToZeroBeforPlaying! {
                self.player?.seek(to: kCMTimeZero)
                self.mSeekToZeroBeforPlaying = false
            }
            self.player?.play()
        }
        else {
            self.player?.pause()
        }
    }

    @IBAction func beginScrubbing(_ sender: Any?) {
        self.mSeekToZeroBeforPlaying = false
        self.mPlayRateToRestore = self.player?.rate
        self.player?.rate = 0.0
        self.removeTimeObserverFromPlayer()
    }
    @IBAction func scrub(_ sender: Any?) {
        self.mLastScrubSliderValue = self.scrubber.value
        if !self.mScrubInFlight! {
            self.scrubToSliderValue(sliderValue: self.mLastScrubSliderValue!)
        }
    }

    @IBAction func endScrubbing(_ sender: Any?) {
        if self.mScrubInFlight! {
            self.scrubToSliderValue(sliderValue: self.mLastScrubSliderValue!)
        }
        self.addTimeObserverToPlayer()
        
        self.player?.rate = self.mPlayRateToRestore!
        self.mPlayRateToRestore = 0.0
    }
    
    func scrubToSliderValue(sliderValue: Float) {
        let duration = CMTimeGetSeconds(self.playerItemDuration())
        if __inline_isfinited(duration) != 0 {
            let width = self.scrubber.bounds.width
            let time = duration * Float64(sliderValue)
            let tolerance = 1.0 * duration / Double(width)
            
            self.mScrubInFlight = true
            
            weak var weakSelf = self
            self.player?.seek(to: CMTimeMakeWithSeconds(time, Int32(NSEC_PER_SEC)),
                              toleranceBefore: CMTimeMakeWithSeconds(tolerance, Int32(NSEC_PER_SEC)),
                              toleranceAfter: CMTimeMakeWithSeconds(tolerance, Int32(NSEC_PER_SEC)),
                              completionHandler: { (finished) in
                weakSelf?.mScrubInFlight = false
                weakSelf?.updateTimeLabel()
            })
        }
    }
    
    func playerItemDidReachEnd(_ notification: Notification) {
        self.mSeekToZeroBeforPlaying = true
    }
}


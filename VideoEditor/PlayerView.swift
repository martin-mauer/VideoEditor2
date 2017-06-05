//
//  PlayerView.swift
//  VideoEditor
//
//  Created by Mobdev125 on 6/3/17.
//  Copyright © 2017 Mobdev125. All rights reserved.
//

import UIKit
import AVFoundation

class PlayerView: UIView {
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var player: AVPlayer {
        get {
            return ((super.layer as? AVPlayerLayer)?.player)!
        }
        set (player) {
            (super.layer as? AVPlayerLayer)?.player = player
        }
    }
}

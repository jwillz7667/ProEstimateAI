//
//  Item.swift
//  ProEstimate AI
//
//  Created by Justin Williams on 3/26/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

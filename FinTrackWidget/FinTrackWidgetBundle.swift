//  FinTrackWidgetBundle.swift — Widget extension entry point

import WidgetKit
import SwiftUI

@main
struct FinTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        FinTrackBalanceWidget()
        FinTrackAccessoryWidget()
        FinTrackRoomWidget()
    }
}

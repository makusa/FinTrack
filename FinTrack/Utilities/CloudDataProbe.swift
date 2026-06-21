//
//  CloudDataProbe.swift
//  FinTrack
//
//  Probes the user's PRIVATE CloudKit database to answer one question:
//  "Does this iCloud account already hold FinTrack data we could restore?"
//
//  Detection keys off an explicit marker record (FinTrackSyncMarker) rather than
//  introspecting SwiftData's internal CD_* mirrored types, which are an
//  implementation detail and would require deployed query indexes. The marker is
//  (re)written whenever the app runs CloudKit-backed, so any device that has ever
//  synced leaves a durable, queryable footprint for a future fresh install.
//

import Foundation
import CloudKit
import os
#if canImport(UIKit)
import UIKit
#endif

enum CloudDataProbe {

    static let containerID = "iCloud.ca.regis.fintrack"

    private static let markerRecordType = "FinTrackSyncMarker"
    private static let markerRecordName = "fintrack-sync-marker"

    private static let log = Logger(subsystem: "ca.regis.fintrack", category: "cloudprobe")

    /// True only when the iCloud account is available AND a FinTrack sync marker
    /// exists in the private database (i.e. there is data worth restoring).
    static func hasCloudData() async -> Bool {
        let container = CKContainer(identifier: containerID)

        let status = try? await container.accountStatus()
        guard status == .available else {
            log.info("hasCloudData: iCloud account unavailable (\(String(describing: status), privacy: .public))")
            return false
        }

        let db = container.privateCloudDatabase
        let id = CKRecord.ID(recordName: markerRecordName)
        do {
            _ = try await db.record(for: id)
            log.info("hasCloudData: marker present")
            return true
        } catch let error as CKError where error.code == .unknownItem {
            // No marker → no prior synced data.
            return false
        } catch {
            log.error("hasCloudData: probe failed (\(error.localizedDescription, privacy: .public))")
            return false
        }
    }

    /// Upserts the sync marker (deviceName + updatedAt). Safe to call on every
    /// CloudKit-backed launch; it's a single lightweight private-DB write.
    static func writeMarker() async {
        let container = CKContainer(identifier: containerID)

        guard (try? await container.accountStatus()) == .available else { return }

        let db = container.privateCloudDatabase
        let id = CKRecord.ID(recordName: markerRecordName)

        let record: CKRecord
        if let existing = try? await db.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: markerRecordType, recordID: id)
        }

        record["updatedAt"] = Date() as CKRecordValue
        #if canImport(UIKit)
        record["deviceName"] = await UIDevice.current.name as CKRecordValue
        #endif

        do {
            _ = try await db.save(record)
            log.info("writeMarker: ok")
        } catch {
            log.error("writeMarker: failed (\(error.localizedDescription, privacy: .public))")
        }
    }
}

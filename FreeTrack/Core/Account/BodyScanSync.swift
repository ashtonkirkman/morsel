import Foundation

// MARK: - Body scans ⇄ account sync
// Only the numbers travel: `BodyScanDTO` carries no photos or keypoints (see docs/BODY_SCAN.md).

extension BodyScanDTO: SyncableDTO {}

extension BodyScan: SyncableModel {
    var syncID: UUID { id }

    func makeDTO() -> BodyScanDTO { dto }

    func apply(_ dto: BodyScanDTO) { update(from: dto) }

    convenience init(syncDTO dto: BodyScanDTO) { self.init(dto: dto) }
}

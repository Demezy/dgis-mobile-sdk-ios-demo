import SwiftUI
import DGis

final class MapObjectCardViewModel: ObservableObject {

	typealias CloseCallback = () -> Void

	@Published var title: String = "Some place" {
		didSet {
			self.titleChangedCallback?(self.title, self.subtitle)
		}
	}
	@Published var description: String

	var objectPosition: GeoPointWithElevation {
		self.objectInfo.closestMapPoint
	}

	var titleChangedCallback: ((String, String) -> Void)? = nil

	private let objectInfo: RenderedObjectInfo
	private let searchManager: SearchManager
	private let dgisSource: DgisSource?
	private let onClose: CloseCallback
	private var getDirectoryObjectCancellable: Cancellable?
	private var subtitle: String = ""
	private var selectedObjectIds: [DgisObjectId] = []

	init(
		objectInfo: RenderedObjectInfo,
		searchManager: SearchManager,
		dgisSource: DgisSource?,
		onClose: @escaping CloseCallback
	) {
		self.objectInfo = objectInfo
		self.searchManager = searchManager
		self.dgisSource = dgisSource
		self.description = objectInfo.description
		self.onClose = onClose
		self.fetchObjectInfo()
	}

	func close() {
		self.onClose()
	}

	func hideObjects() {
		self.dgisSource?.setHighlighted(directoryObjectIds: self.selectedObjectIds, highlighted: false)
		self.selectedObjectIds.removeAll()
	}

	private func fetchObjectInfo() {
		let mapObject = self.objectInfo.item.item
		switch mapObject {
			case let object as DgisMapObject:
				self.fetchInfo(dgisMapObject: object)
			case let marker as Marker:
				self.fetchInfo(marker: marker)
			default:
				self.fetchInfo(objectInfo: self.objectInfo)
		}
	}

	private func fetchInfo(dgisMapObject object: DgisMapObject) {
		let future = searchManager.searchByDirectoryObjectId(objectId: object.id)
		
		self.getDirectoryObjectCancellable = future.sinkOnMainThread(
			receiveValue: {
				[weak self] directoryObject in
				guard let self = self else { return }
				guard let directoryObject = directoryObject else { return }

				self.subtitle = directoryObject.subtitle
				self.title = directoryObject.title
				self.description = """
					\(directoryObject.subtitle)
					\(directoryObject.formattedAddress(type: .short)?.streetAddress ?? "(no address)")
					\(directoryObject.markerPosition?.description ?? "(no location)")
					ID: \(object.id.objectId)
					"""

				if let objectId = directoryObject.id {
					self.selectedObjectIds = [objectId]
					directoryObject.entrances.forEach { entrance in
						self.selectedObjectIds.append(entrance.id)
					}
					self.dgisSource?.setHighlighted(directoryObjectIds: self.selectedObjectIds, highlighted: true)
				}
			},
			failure: { error in
				print("Unable to fetch a directory object. Error: \(error).")
			}
		)
	}

	private func fetchInfo(marker: Marker) {
		let text = marker.text
		self.subtitle = "\(marker.position)"
		self.title = text.isEmpty ? "Marker" : text
		self.description = "\(marker.position)"
	}

	private func fetchInfo(objectInfo: RenderedObjectInfo) {
		self.title = String(describing: type(of: objectInfo))
		self.description = String(describing: objectInfo)
	}
}

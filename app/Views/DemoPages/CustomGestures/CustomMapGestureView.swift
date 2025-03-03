import UIKit
import DGis

class LoggingMapEventProcessorProxy : IMapEventProcessor {
    private let processor: IMapEventProcessor
    
    init(processor: IMapEventProcessor){
        self.processor = processor
    }
    
    @available(iOS 16.0, *)
    private func logProcess(event: DGis.Event){
        let eventType = String(describing: type(of: event))
        let timestamp = Date().timeIntervalSince1970
        debugPrint("FLAG1: LoggingMapEventProcessorProxy: \(eventType), timestamp: \(timestamp)")
        self.processor.process(event: event)
    }
    
    
    func process(event: DGis.Event) {
        if #available(iOS 16.0, *) {
            logProcess(event:  event)
        } else {
            self.processor.process(event: event)
        }
    }
    
    
}

class CustomMapGestureView: UIView, IMapGestureView {
	private(set) var panGestureRecognizer: UIPanGestureRecognizer?
	private(set) var pinchGestureRecognizer: UIPinchGestureRecognizer?

	var rotationGestureRecognizer: UIRotationGestureRecognizer? {
		self.defaultMapGestureView?.rotationGestureRecognizer
	}

	private let mapEventProcessor: IMapEventProcessor
	private let mapCoordinateSpace: IMapCoordinateSpace
	private let defaultMapGestureView: IMapGestureView?

    init(
        map: Map,
        mapEventProcessor: IMapEventProcessor,
        mapCoordinateSpace: IMapCoordinateSpace
    ) {
        debugPrint("FLAG1: Initializing CustomMapGestureView")
        self.mapEventProcessor = LoggingMapEventProcessorProxy(processor: mapEventProcessor)
        self.mapCoordinateSpace = mapCoordinateSpace
        let gestureViewFactory = MapOptions.default.gestureViewFactory
        debugPrint("FLAG1: Creating default gesture view")
        self.defaultMapGestureView = gestureViewFactory?.makeGestureView(
            map: map,
            eventProcessor: mapEventProcessor,
            coordinateSpace: mapCoordinateSpace
        )
        super.init(frame: .zero)

		self.setupGestureRecognizers()
	}

	required init?(coder: NSCoder) {
		fatalError("Use init(mapEventProcessor:)")
	}

	private func setupGestureRecognizers() {
		self.isMultipleTouchEnabled = true

		let panGR = UIPanGestureRecognizer(target: self, action: #selector(self.pan))
		panGR.delegate = self
		self.addGestureRecognizer(panGR)
		self.panGestureRecognizer = panGR

		let pinchGR = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch))
		pinchGR.delegate = self
		self.addGestureRecognizer(pinchGR)
		self.pinchGestureRecognizer = pinchGR

		self.rotationGestureRecognizer.map(self.addGestureRecognizer)
	}

	@objc func pinch(_ pinchGestureRecognizer: UIPinchGestureRecognizer) {
		switch pinchGestureRecognizer.state {
			case .began:
				self.mapEventProcessor.process(event: DirectMapControlBeginEvent())
			case .changed:
				let scalingCenter = self.center
				let scaleDelta = pinchGestureRecognizer.scale
				let convertedScalingCenter = self.convert(scalingCenter, to: self.mapCoordinateSpace)
					.applying(self.mapCoordinateSpace.toPixels)

				// There is a difference between zoom and scale.
				// Their relationship is subject to the formula: scale = C*exp(2, zoom).
				// To send an event, it is necessary to change the scale,
				// expressed in terms of the logarithm of the change in the multiplier.
				let zoomDelta = Float(log2(scaleDelta))
				let center = ScreenPoint(convertedScalingCenter)
				let event = DirectMapScalingEvent(
					zoomDelta: zoomDelta,
					timestamp: .now(),
					scalingCenter: center
				)
				self.mapEventProcessor.process(event: event)

				pinchGestureRecognizer.scale = 1
			case .ended:
				self.mapEventProcessor.process(event: DirectMapControlEndEvent(timestamp: .now()))
			case .cancelled, .failed:
				self.mapEventProcessor.process(event: CancelEvent())
			default:
				break
		}
	}

	@objc func pan(_ panGestureRecognizer: UIPanGestureRecognizer) {
		switch panGestureRecognizer.state {
			case .began:
				self.mapEventProcessor.process(event: DirectMapControlBeginEvent())
			case .changed:
				let location = panGestureRecognizer.location(in: self)
				let translation = panGestureRecognizer.translation(in: self)
				let targetLocation = self.convert(location, to: self.mapCoordinateSpace)
				let from = CGPoint(
					x: targetLocation.x - translation.x,
					y: targetLocation.y - translation.y
				)

                if from != targetLocation {
                    debugPrint("FLAG1: Processing pan movement")
                    let toPixels = self.mapCoordinateSpace.toPixels
                    let from = from.applying(toPixels)
                    let location = targetLocation.applying(toPixels)
                    let vector = CGVector(
                        dx: location.x - from.x,
                        dy: location.y - from.y
                    )
                    debugPrint("FLAG1: Pan vector - dx: \(vector.dx), dy: \(vector.dy)")
                    let fromPoint = ScreenPoint(from)
                    let shift = ScreenShift(vector)
                    let event = DirectMapShiftEvent(
                        screenShift: shift,
                        shiftedPoint: fromPoint,
                        timestamp: .now()
                    )
                    self.mapEventProcessor.process(event: event)
                }
                panGestureRecognizer.setTranslation(.zero, in: self)
            case .ended:
                debugPrint("FLAG1: Pan ended")
                self.mapEventProcessor.process(event: DirectMapControlEndEvent(timestamp: .now()))
            case .cancelled, .failed:
                debugPrint("FLAG1: Pan cancelled/failed")
                self.mapEventProcessor.process(event: CancelEvent())
            default:
                debugPrint("FLAG1: Pan other state: \(panGestureRecognizer.state.rawValue)")
                break
        }
    }
}

extension CustomMapGestureView: UIGestureRecognizerDelegate {
	func gestureRecognizer(
		_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
	) -> Bool {
		true
	}
}

private extension TimeInterval {
	static func now() -> TimeInterval {
		TimeInterval(CACurrentMediaTime())
	}
}

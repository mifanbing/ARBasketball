import UIKit
import SceneKit
import ARKit
import Vision

typealias VisionVNRecognizedPointKey = Vision.VNRecognizedPointKey

class MainViewController: UIViewController, ARSCNViewDelegate {
    @IBOutlet var sceneView: ARSCNView!
    
    let dispatchQueueML = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var gestureProcessor = HandGestureProcessor()
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    private var lastObservationTimestamp = Date()
    
    var redBoxThumb = UIView()
    var redBoxIndex = UIView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        let scene = SCNScene()
        sceneView.scene = scene
        
        handPoseRequest.maximumHandCount = 1
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()

        sceneView.session.run(configuration)
        let motherBall = SCNSphere(radius: CGFloat(0.02))
        let ballMaterial = SCNMaterial()
        ballMaterial.diffuse.contents = UIColor.white
        motherBall.materials = [ballMaterial]
        
        let motherBallNode = SCNNode()
        motherBallNode.position = SCNVector3(0, 0, -1)
        motherBallNode.geometry = motherBall
        sceneView.scene.rootNode.addChildNode(motherBallNode)
        
        loopCoreMLUpdate()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    func loopCoreMLUpdate() {
        dispatchQueueML.async {
            self.updateCoreML()
            self.loopCoreMLUpdate()
        }
    }
}

extension MainViewController {
    func updateCoreML() {
        guard let pixbuff = sceneView.session.currentFrame?.capturedImage else { return }

        var thumbTip: CGPoint?
        var indexTip: CGPoint?
        
        defer {
            DispatchQueue.main.sync {
                self.processPoints(thumbTip: thumbTip, indexTip: indexTip)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixbuff, options: [:])
        do {
            // Perform VNDetectHumanHandPoseRequest
            try handler.perform([handPoseRequest])
            // Continue only when a hand was detected in the frame.
            // Since we set the maximumHandCount property of the request to 1, there will be at most one observation.
            guard let observation = handPoseRequest.results?.first as? VNRecognizedPointsObservation else {
                return
            }
            // Get points for thumb and index finger.
            let thumbPoints: [VisionVNRecognizedPointKey : VNRecognizedPoint] = try observation.recognizedPoints(forGroupKey: .handLandmarkRegionKeyThumb)
            let indexFingerPoints: [VisionVNRecognizedPointKey : VNRecognizedPoint] = try observation.recognizedPoints(forGroupKey: .handLandmarkRegionKeyIndexFinger)
//            // Look for tip points.
            guard let thumbTipPoint = thumbPoints[VisionVNRecognizedPointKey(string: "VNHLKTTIP")], let indexTipPoint = indexFingerPoints[VisionVNRecognizedPointKey(string: "VNHLKITIP")] else {
                return
            }
            // Ignore low confidence points.
            guard thumbTipPoint.confidence > 0.3 && indexTipPoint.confidence > 0.3 else {
                return
            }
            // Convert points from Vision coordinates to AVFoundation coordinates.
            thumbTip = CGPoint(x: thumbTipPoint.location.x, y: thumbTipPoint.location.y)
            indexTip = CGPoint(x: indexTipPoint.location.x, y: indexTipPoint.location.y)
            
            
        } catch {
//            cameraFeedSession?.stopRunning()
//            let error = AppError.visionError(error: error)
//            DispatchQueue.main.async {
//                error.displayInViewController(self)
        }
    }
    
    func processPoints(thumbTip: CGPoint?, indexTip: CGPoint?) {
        // Check that we have both points.
        guard let thumbPoint = thumbTip, let indexPoint = indexTip else {
            // If there were no observations for more than 2 seconds reset gesture processor.
            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
                gestureProcessor.reset()
            }
            //cameraView.showPoints([], color: .clear)
            return
        }
        
        redBoxThumb.removeFromSuperview()
        redBoxIndex.removeFromSuperview()
        
        //redBoxThumb = UIView(frame: CGRect(x: thumbPoint.x * sceneView.frame.width, y: thumbPoint.y * sceneView.frame.height, width: 5, height: 5))
        redBoxThumb = UIView(frame: CGRect(x: thumbPoint.y * sceneView.frame.height, y: thumbPoint.x * sceneView.frame.width, width: 5, height: 5))
        redBoxThumb.backgroundColor = .red
        sceneView.addSubview(redBoxThumb)
        
        //redBoxIndex = UIView(frame: CGRect(x: indexPoint.x * sceneView.frame.width, y: indexPoint.y * sceneView.frame.height, width: 5, height: 5))
        redBoxIndex = UIView(frame: CGRect(x: indexPoint.y * sceneView.frame.height, y: indexPoint.x * sceneView.frame.width, width: 5, height: 5))
        
        redBoxIndex.backgroundColor = .red
        sceneView.addSubview(redBoxIndex)
        
        // Convert points from AVFoundation coordinates to UIKit coordinates.
//        let previewLayer = cameraView.previewLayer
//        let thumbPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: thumbPoint)
//        let indexPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: indexPoint)
//
//        // Process new points
//        gestureProcessor.processPointsPair((thumbPoint, indexPoint))
    }
}

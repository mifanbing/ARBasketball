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
    
    var motherBallNode = SCNNode()
    var currentBallCoordinate: SCNVector3!
    
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
        
        redBoxThumb = UIView(frame: CGRect(x: thumbPoint.y * sceneView.frame.width, y: thumbPoint.x * sceneView.frame.height, width: 5, height: 5))
        redBoxThumb.backgroundColor = .red
        sceneView.addSubview(redBoxThumb)
        
        redBoxIndex = UIView(frame: CGRect(x: indexPoint.y * sceneView.frame.width, y: indexPoint.x * sceneView.frame.height, width: 5, height: 5))
        
        redBoxIndex.backgroundColor = .red
        sceneView.addSubview(redBoxIndex)
        
        currentBallCoordinate = sceneView.projectPoint(motherBallNode.position)
        
        let indexX = indexPoint.y * sceneView.frame.width
        let indexY = indexPoint.x * sceneView.frame.height
        let deltaX = CGFloat(currentBallCoordinate.x) - indexX
        let deltaY = CGFloat(currentBallCoordinate.y) - indexY
        
        print(currentBallCoordinate)
        print("\(indexX) \(indexY)")
        print("---")
        
        if abs(deltaX) < 80.0 && abs(deltaY) < 80.0 {
            print("touch!!!")
            let direction = SCNVector3(deltaX, deltaY, 0).normalized
            
            guard let currentTranform = sceneView.session.currentFrame?.camera.transform else { return }
            
            let directionShit = SIMD4<Float>.init(x: direction.x, y: direction.y, z: 0, w: 0)
            let directionTransformed = currentTranform * directionShit
            
            motherBallNode.runAction(SCNAction.moveBy(x: CGFloat(directionTransformed.x * 0.1),
                                                      y: CGFloat(directionTransformed.y * 0.1),
                                                      z: CGFloat(directionTransformed.z * 0.1),
                                                      duration: 0.1))
            currentBallCoordinate = SCNVector3(currentBallCoordinate.x + directionTransformed.x * 0.1,
                                               currentBallCoordinate.y + directionTransformed.y * 0.1,
                                               0)
        }
    }
}

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
    var isDragging = false
    var isTouching = false
    var lastIndexTipPoint: CGPoint?
    
    var motherBallNode = SCNNode()
    var currentBallCoordinate: SCNVector3!
    
    var redBoxIndexTip = UIView()
    var redBoxIndexMid = UIView()
    var redBoxIndexMidRoot = UIView()
    var redBoxIndexRoot = UIView()
    
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
        
        motherBallNode.position = SCNVector3(0, 0, -0.3)
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
        
        var indexTip: CGPoint?
        var indexMid: CGPoint?
        var indexMidRoot: CGPoint?
        var indexRoot: CGPoint?
        
        defer {
            DispatchQueue.main.sync {
                self.processPoints(indexTip: indexTip, indexMid: indexMid, indexMidRoot: indexMidRoot, indexRoot: indexRoot)
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
            let indexFingerPoints: [VisionVNRecognizedPointKey : VNRecognizedPoint] = try observation.recognizedPoints(forGroupKey: .handLandmarkRegionKeyIndexFinger)
            // Look for tip points.
            // root to tip
            // thumbPoints: VNHLKTCMC VNHLKTIP VNHLKTMP VNHLKTTIP
            // indexFingerPoints: VNHLKIMCP VNHLKIPIP VNHLKIDIP VNHLKITIP
            guard let indexTipPoint = indexFingerPoints[VisionVNRecognizedPointKey(string: "VNHLKITIP")],
                  let indexMidPoint = indexFingerPoints[VisionVNRecognizedPointKey(string: "VNHLKIDIP")],
                  let indexMidRootPoint = indexFingerPoints[VisionVNRecognizedPointKey(string: "VNHLKIPIP")],
                  let indexRootPoint = indexFingerPoints[VisionVNRecognizedPointKey(string: "VNHLKIMCP")] else {
                return
            }
            // Ignore low confidence points.
            guard indexTipPoint.confidence > 0.3
                    && indexMidPoint.confidence > 0.3
                    && indexMidRootPoint.confidence > 0.3
                    && indexRootPoint.confidence > 0.3 else {
                return
            }
            // Convert points from Vision coordinates to AVFoundation coordinates.
            indexTip = CGPoint(x: indexTipPoint.location.x, y: indexTipPoint.location.y)
            indexMid = CGPoint(x: indexMidPoint.location.x, y: indexMidPoint.location.y)
            indexMidRoot = CGPoint(x: indexMidRootPoint.location.x, y: indexMidRootPoint.location.y)
            indexRoot = CGPoint(x: indexRootPoint.location.x, y: indexRootPoint.location.y)
        } catch {
            
        }
    }
    
    func processPoints(indexTip: CGPoint?, indexMid: CGPoint?, indexMidRoot: CGPoint?, indexRoot: CGPoint?) {
        // Check that we have both points.
        guard let indexTipPoint = indexTip, let indexMidPoint = indexMid, let indexMidRootPoint = indexMidRoot, let indexRootPoint = indexRoot else {
            // If there were no observations for more than 2 seconds reset gesture processor.
            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
                gestureProcessor.reset()
            }
            //cameraView.showPoints([], color: .clear)
            return
        }
        
        redBoxIndexTip.removeFromSuperview()
        redBoxIndexTip = UIView(frame: CGRect(x: indexTipPoint.y * sceneView.frame.width, y: indexTipPoint.x * sceneView.frame.height, width: 5, height: 5))
        redBoxIndexTip.backgroundColor = .red
        sceneView.addSubview(redBoxIndexTip)
        
        redBoxIndexMid.removeFromSuperview()
        redBoxIndexMid = UIView(frame: CGRect(x: indexMidPoint.y * sceneView.frame.width, y: indexMidPoint.x * sceneView.frame.height, width: 5, height: 5))
        redBoxIndexMid.backgroundColor = .red
        sceneView.addSubview(redBoxIndexMid)
        
        redBoxIndexMidRoot.removeFromSuperview()
        redBoxIndexMidRoot = UIView(frame: CGRect(x: indexMidRootPoint.y * sceneView.frame.width, y: indexMidRootPoint.x * sceneView.frame.height, width: 5, height: 5))
        redBoxIndexMidRoot.backgroundColor = .red
        sceneView.addSubview(redBoxIndexMidRoot)
        
        redBoxIndexRoot.removeFromSuperview()
        redBoxIndexRoot = UIView(frame: CGRect(x: indexRootPoint.y * sceneView.frame.width, y: indexRootPoint.x * sceneView.frame.height, width: 5, height: 5))
        redBoxIndexRoot.backgroundColor = .red
        sceneView.addSubview(redBoxIndexRoot)
        
        currentBallCoordinate = sceneView.projectPoint(motherBallNode.position)
        
        let indexX = indexTipPoint.y * sceneView.frame.width
        let indexY = indexTipPoint.x * sceneView.frame.height
        let deltaX = CGFloat(currentBallCoordinate.x) - indexX
        let deltaY = CGFloat(currentBallCoordinate.y) - indexY
        
        let radius = calculateThings()
        
        if isTouching {
            isDragging = isCurved(indexTip: indexTipPoint, indexMid: indexMidPoint, indexMidRoot: indexMidRootPoint, indexRoot: indexRootPoint)
            
            if isDragging {
                let moveX = indexX - lastIndexTipPoint!.x
                let moveY = indexY - lastIndexTipPoint!.y

                let direction = SCNVector3(moveX, moveY, 0).normalized

                guard let currentTranform = sceneView.session.currentFrame?.camera.transform else { return }

                let directionShit = SIMD4<Float>.init(x: direction.x, y: direction.y, z: 0, w: 0)
                let directionTransformed = currentTranform.inverse * directionShit
                
                print("Camera: \(direction) Transformed: \(directionTransformed)")

                motherBallNode.runAction(SCNAction.moveBy(x: CGFloat(directionTransformed.x) * 0.01,
                                                          y: CGFloat(directionTransformed.y) * 0.01,
                                                          z: CGFloat(directionTransformed.z) * 0.01,
                                                          duration: 0.2))
                currentBallCoordinate = SCNVector3(currentBallCoordinate.x + directionTransformed.x * 0.01,
                                                   currentBallCoordinate.y + directionTransformed.y * 0.01,
                                                   currentBallCoordinate.z + directionTransformed.z * 0.01)
            }
        }
        
        if !isDragging {
            isTouching = deltaX * deltaX + deltaY * deltaY < radius * radius
        }
        
        lastIndexTipPoint = indexTipPoint
    }
    
    private func calculateThings() -> CGFloat {
        let positiveX = SCNVector3(motherBallNode.position.x + 1,
                                   motherBallNode.position.y,
                                   motherBallNode.position.z)
        let ballCoordinatePositiveX = sceneView.projectPoint(positiveX)
        let positiveY = SCNVector3(motherBallNode.position.x,
                                   motherBallNode.position.y + 1,
                                   motherBallNode.position.z)
        let ballCoordinatePositiveY = sceneView.projectPoint(positiveY)
        let positiveZ = SCNVector3(motherBallNode.position.x,
                                   motherBallNode.position.y,
                                   motherBallNode.position.z + 1)
        let ballCoordinatePositiveZ = sceneView.projectPoint(positiveZ)
        
        let x1 = ballCoordinatePositiveX.x
        let y1 = ballCoordinatePositiveX.y
        let x2 = ballCoordinatePositiveY.x
        let y2 = ballCoordinatePositiveY.y
        let x3 = ballCoordinatePositiveZ.x
        let y3 = ballCoordinatePositiveZ.y

        let A = y2 / (x1 * y2 - x2 * y1)
        let B = y1 / (x1 * y2 - x2 * y1)
        let C = y3 / (x1 * y3 - x3 * y1)
        let D = y1 / (x1 * y3 - x3 * y1)
        
        let k = (C.power(exponential: 2) + D.power(exponential: 2) - A * C) / (A.power(exponential: 2) + B.power(exponential: 2) + C.power(exponential: 2) + D.power(exponential: 2) - 2 * A * C)
        
        let length = sqrt((k * A + (1 - k) * C).power(exponential: 2) + (k * B).power(exponential: 2) + (D - k * D).power(exponential: 2))
        
        let radius = CGFloat(0.02 / length)
        
        return radius
    }
    
    private func isCurved(indexTip: CGPoint, indexMid: CGPoint, indexMidRoot: CGPoint, indexRoot: CGPoint) -> Bool {
        let angle1 = angle(point1: indexTip, point2: indexMid, point3: indexMidRoot)
        let angle2 = angle(point1: indexMid, point2: indexMidRoot, point3: indexRoot)
        
        return angle1 + angle2 > 60
    }
    
    private func angle(point1: CGPoint, point2: CGPoint, point3: CGPoint) -> CGFloat {
        let line12X = point2.x - point1.x
        let line12Y = point2.y - point1.y
        let line23X = point3.x - point2.x
        let line23Y = point3.y - point2.y
        
        let length1 = sqrt(line12X * line12X + line12Y * line12Y)
        let length2 = sqrt(line23X * line23X + line23Y * line23Y)
        let cosTheta = (line12X * line23X + line12Y * line23Y) / (length1 * length2)
        
        //could be negative but i dont care
        let theta = acos(cosTheta) * 180 / CGFloat.pi
        
        return theta
    }
    
}

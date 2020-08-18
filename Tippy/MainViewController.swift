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
    var handState: HandState = .nonTouching
    var ballState: BallState = .still
    var lastIndexTipPoint: CGPoint?
    
    var motherBallNode = BallNode()
    var currentBallCoordinate: SCNVector3!
    
    var redBoxIndexTip = UIView()
    var redBoxIndexMid = UIView()
    var redBoxIndexMidRoot = UIView()
    var redBoxIndexRoot = UIView()
    
    var timer = Timer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        let scene = SCNScene()
        sceneView.scene = scene
        
        handPoseRequest.maximumHandCount = 1
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sceneView.scene.physicsWorld.contactDelegate = self
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)

        setupNodes()
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
    
    @objc func updateTimer() {
        //print("Timer fired!")
        motherBallNode.update()
    }
}

extension MainViewController: SCNPhysicsContactDelegate {
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        timer.invalidate()
        
        let nodeA = (contact.nodeA as! ContactNode)
        let nodeB = (contact.nodeB as! ContactNode)
        if nodeA.contactList.contains(nodeB.name!) || nodeB.contactList.contains(nodeA.name!) {
            return
        }
        
        nodeA.contactList.append(nodeB.name!)
        nodeB.contactList.append(nodeA.name!)
        
        let ballNode = (nodeA.name == "ball" ? nodeA : nodeB) as! BallNode
        if ballNode.actionKeys.contains("ShootBall") {
            ballNode.removeAction(forKey: "ShootBall")
        }
        
        let normal = contact.contactNormal
        let normalVelocity = ballNode.ballVelocity.normalComponent(wrt: normal).scale(by: -1)
        let tangentVelocity = ballNode.ballVelocity.tangentComponent(wrt: normal)
        let reflectedVelocity = normalVelocity.add(v: tangentVelocity)
        
        ballNode.runAction(SCNAction.moveBy(x: CGFloat(reflectedVelocity.x * 2),
                                            y: CGFloat(reflectedVelocity.y * 2),
                                            z: CGFloat(reflectedVelocity.z * 2),
                                            duration: 2)) {
            self.ballState = .still
            self.currentBallCoordinate = self.motherBallNode.position
        }
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        let nodeA = (contact.nodeA as! ContactNode)
        let nodeB = (contact.nodeB as! ContactNode)
        
        let ballNode = nodeA.name == "ball" ? nodeA : nodeB
        ballNode.contactList.removeAll(where: { $0 == "board" })
        let boardNode = nodeA.name == "board" ? nodeA : nodeB
        boardNode.contactList.removeAll(where: { $0 == "ball" })
        
    }
}

extension MainViewController {
    func setupNodes() {
        //setup motherBall
        let motherBall = SCNSphere(radius: CGFloat(0.02))
        let ballMaterial = SCNMaterial()
        ballMaterial.diffuse.contents = UIImage(named: "ball.jpeg")
        motherBall.materials = [ballMaterial]
        
        motherBallNode.position = SCNVector3(0, 0, -0.3)
        motherBallNode.geometry = motherBall
        motherBallNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: motherBall, options: nil))
        motherBallNode.physicsBody?.categoryBitMask = 2
        motherBallNode.physicsBody?.contactTestBitMask = 1
        motherBallNode.physicsBody?.collisionBitMask = 1
        motherBallNode.name = "ball"
        sceneView.scene.rootNode.addChildNode(motherBallNode)
        
        //setup walls
        let board = SCNPlane(width: 1, height: 1)
        let boardMaterial = SCNMaterial()
        boardMaterial.diffuse.contents = UIColor(red: 0, green: 1, blue: 0, alpha: 0.8)
        board.materials = [boardMaterial]
        
        let boardNode = ContactNode()
        boardNode.position = SCNVector3(0, 0.3, -1)
        boardNode.geometry = board
        boardNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: board, options: nil))
        boardNode.physicsBody?.categoryBitMask = 1
        boardNode.physicsBody?.contactTestBitMask = 2
        boardNode.physicsBody?.collisionBitMask = 2
        boardNode.name = "board"
        sceneView.scene.rootNode.addChildNode(boardNode)
    }
    
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
        drawJoints(indexTipPoint: indexTipPoint, indexMidPoint: indexMidPoint, indexMidRootPoint: indexMidRootPoint, indexRootPoint: indexRootPoint)
        
        currentBallCoordinate = sceneView.projectPoint(motherBallNode.position)
        
        let indexX = indexTipPoint.y * sceneView.frame.width
        let indexY = indexTipPoint.x * sceneView.frame.height
        let deltaX = CGFloat(currentBallCoordinate.x) - indexX
        let deltaY = CGFloat(currentBallCoordinate.y) - indexY
        
        let radius = calculateBallRadius()
        let shouldShoot = shouldShootBall(indexTip: indexTipPoint, indexMid: indexMidPoint, indexMidRoot: indexMidRootPoint, indexRoot: indexRootPoint)
        let shouldDrag = shouldDragBall(indexTip: indexTipPoint, indexMid: indexMidPoint, indexMidRoot: indexMidRootPoint, indexRoot: indexRootPoint)
        
        //update ballstate
        switch handState {
        case .nonTouching: ()
        case .touching:
            if shouldShoot  {
                print("Shoot")
                timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)
            
                ballState = .shooting
                let velocities = shootBall(cameraTransform: sceneView.session.currentFrame!.camera.transform)

                let actions = velocities.map { velocity in
                    SCNAction.moveBy(x: CGFloat(velocity.x * 0.01),
                                     y: CGFloat(velocity.y * 0.01),
                                     z: CGFloat(velocity.z * 0.01),
                                     duration: 0.01)
                }
                motherBallNode.shootBall(ballVelocity: velocities[0])
                
                let sequenceAction = SCNAction.sequence(actions)
                motherBallNode.runAction(sequenceAction, forKey: "ShootBall") {
                    self.ballState = .still
                    self.currentBallCoordinate = self.motherBallNode.position
                    self.timer.invalidate()
                    print("Shoot End")
                }
                
            } else if shouldDrag {
                ballState = .dragging
                let moveX = indexX - lastIndexTipPoint!.y * sceneView.frame.width
                let moveY = indexY - lastIndexTipPoint!.x * sceneView.frame.height

                let moveVector = dragBall(deltaX: Float(moveX), deltaY: Float(moveY))

                motherBallNode.runAction(SCNAction.moveBy(x: CGFloat(moveVector.x),
                                                          y: CGFloat(moveVector.y),
                                                          z: CGFloat(moveVector.z),
                                                          duration: 0.2))
                currentBallCoordinate = SCNVector3(currentBallCoordinate.x + moveVector.x,
                                                   currentBallCoordinate.y + moveVector.y,
                                                   currentBallCoordinate.z + moveVector.z)
            } else {
                ballState = .still
            }
        }
        
        //update hand state
        switch ballState {
        case .shooting:
            handState = .nonTouching
        case .dragging:
            handState = shouldDrag ? .touching : .nonTouching
        case .still:
            handState = deltaX * deltaX + deltaY * deltaY < radius * radius ? .touching : .nonTouching
        }
   
        lastIndexTipPoint = indexTipPoint
    }
}

extension MainViewController {
    private func drawJoints(indexTipPoint: CGPoint, indexMidPoint: CGPoint, indexMidRootPoint: CGPoint, indexRootPoint: CGPoint) {
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
    }
    
    //calculate ball radius in camera frame
    private func calculateBallRadius() -> CGFloat {
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
    
    private func shouldDragBall(indexTip: CGPoint, indexMid: CGPoint, indexMidRoot: CGPoint, indexRoot: CGPoint) -> Bool {
        let angle1 = angle(point1: indexTip, point2: indexMid, point3: indexMidRoot)
        let angle2 = angle(point1: indexMid, point2: indexMidRoot, point3: indexRoot)
        
        return angle1 + angle2 > 60
    }
    
    private func shouldShootBall(indexTip: CGPoint, indexMid: CGPoint, indexMidRoot: CGPoint, indexRoot: CGPoint) -> Bool {
        let angle1 = angle(point1: indexTip, point2: indexMid, point3: indexMidRoot)
        let angle2 = angle(point1: indexMid, point2: indexMidRoot, point3: indexRoot)
        
        return angle1 + angle2 > 100
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
    
    //drag ball in 3d space to match the hand movement in the camera frame
    private func dragBall(deltaX: Float, deltaY: Float) -> SCNVector3 {
        let cameraTransform = sceneView.session.currentFrame!.camera.transform
        let column0 = cameraTransform.columns.0
        let cameraXDirection = SCNVector3(column0[0], column0[1], column0[2]).normalized
        let column1 = cameraTransform.columns.1
        let cameraYDirection = SCNVector3(column1[0], column1[1], column1[2]).normalized
        
        let shit1 = motherBallNode.position.add(v: cameraXDirection)
        let shit2 = motherBallNode.position.add(v: cameraYDirection)
        
        let cameraXDirectionProject = sceneView.projectPoint(shit1)
        let cameraYDirectionProject = sceneView.projectPoint(shit2)
        
        let x1 = cameraXDirectionProject.x
        let y1 = cameraXDirectionProject.y
        let x2 = cameraYDirectionProject.x
        let y2 = cameraYDirectionProject.y
        
        let A = deltaX * y2 / (x1 * y2 - x2 * y1)
        let B = -deltaX * y1 / (x1 * y2 - x2 * y1)
        let C = deltaY * x2 / (x2 * y1 - x1 * y2)
        let D = -deltaY * x1 / (x2 * y1 - x1 * y2)
        
        let xMove = cameraXDirection.scale(by: A + C)
        let yMove = cameraYDirection.scale(by: B + D)
        
        return xMove.add(v: yMove)
    }
    
    //shoot ball under faked gravity
    private func shootBall(cameraTransform: simd_float4x4) -> [SCNVector3] {
        //X axis is pointing top. 
        let xAxis = cameraTransform.columns.0
        //let yAxis = cameraTransform.columns.1
        let zAxis = cameraTransform.columns.2
        let xAxisVector = SCNVector3(xAxis[0], xAxis[1], xAxis[2])
        //let yAxisVector = SCNVector3(yAxis[0], yAxis[1], yAxis[2])
        let zAxisVector = SCNVector3(-zAxis[0], -zAxis[1], -zAxis[2])
        
        let cosTheta = sqrt(zAxis[2].power(exponential: 2)) / sqrt(zAxis[0].power(exponential: 2) + zAxis[1].power(exponential: 2) + zAxis[2].power(exponential: 2))
        
        let v0: Float = 0.5
        let gConstant: Float = 9.8 / 40
        let theta = acos(cosTheta) + Float.pi / 6
        let deltaTime: Float = 0.01
        var velocityOverTime = [SCNVector3]()
        var timeNow: Float = 0.0
        
        
        let vZ = v0 * cos(theta)
        let vX = -v0 * sin(theta)
        
        let vInit = xAxisVector.scale(by: vX).add(v: zAxisVector.scale(by: vZ))
        let timeTotal: Float = 2.0 * vInit.y / gConstant
        
        print("angle: \(theta * 180 / 3.14) time: \(timeTotal)")
        
        while timeNow < timeTotal {
            let velocity = xAxisVector.scale(by: vX).add(v: zAxisVector.scale(by: vZ)).add(v: SCNVector3(0, -gConstant * timeNow, 0))
            velocityOverTime.append(velocity)
            timeNow = timeNow + deltaTime
        }
        
        return velocityOverTime
    }
}

import SceneKit

class BallNode: ContactNode {
    var ballVelocity = SCNVector3(1, 0, 0)
    let gConstant: Float = 9.8 / 40
    let deltaTime: Float = 0.1
    
    func shootBall(ballVelocity: SCNVector3) {
        self.ballVelocity = ballVelocity
    }
    
    func update() {
        ballVelocity = ballVelocity.add(v: SCNVector3(0, -gConstant * deltaTime, 0))
    }
}

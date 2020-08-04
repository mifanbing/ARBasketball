import SceneKit

extension Float {
    func power(exponential: Int) -> Float {
        var answer: Float = 1.0
        for _ in 0..<exponential {
            answer = answer * self
        }
        return answer
    }
}

extension SCNVector3 {
    var length: Float {
        return sqrt(x.power(exponential: 2) + y.power(exponential: 2) + z.power(exponential: 2))
    }
    
    var normalized: SCNVector3 {
        return SCNVector3(x / length, y / length, z / length)
    }
    
    var negative: SCNVector3 {
        return SCNVector3(-x, -y, -z)
    }
    
    var xzPlane: SCNVector3 {
        return SCNVector3(x, 0, z).normalized
    }
    
    func rotationByY(degree: Float) -> SCNVector3 {
        let xRotate = x * cos(degree) - z * sin(degree)
        let zRotate = x * sin(degree) + z * cos(degree)
        
        return SCNVector3(xRotate, y, zRotate)
    }
    
    func dot(vector: SCNVector3) -> Float {
        return x * vector.x + y * vector.y + z * vector.z
    }
    
    func normalComponent(wrt vector: SCNVector3) -> SCNVector3 {
        let vector = vector.normalized
        let length = self.dot(vector: vector)
        
        return SCNVector3(x: vector.x * length, y: vector.y * length, z: vector.z * length)
    }
    
    func tangentComponent(wrt vector: SCNVector3) -> SCNVector3 {
        let vector = vector.normalized
        let normal = normalComponent(wrt: vector)
        
        return SCNVector3(x: x - normal.x, y: y - normal.y, z: z - normal.z)
    }
}

extension Int {
    static func rowAndNumber(index: Int) -> (Int, Int) {
        let row = Int(ceil( (sqrt(Double(8 * index + 1)) - 1) / 2 ))
        
        let number: Int = (index - row * (row - 1) / 2)
        
        return (row, number)
    }
    
    static func offsetFromFirst(index: Int, space: Float) -> (Float, Float) {
        let (row, number) = rowAndNumber(index: index)
        let xOffset: Float = (Float(row) - 1) * sqrt(3) / 2 * space
        let zOffset: Float = (Float(row) - 1) / 2 * space - Float(number - 1) * space
        
        return (xOffset, zOffset)
    }
}

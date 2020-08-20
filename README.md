Integrate iOS 14 hand detection with AR kit to play baskteball.

![alt text](https://github.com/mifanbing/Tipy/blob/master/picture2.png)

Desired behavior:
1. The camera will detect the index finger. 
2. When you touch the ball, you can drag the ball with your index finger when curling a little. When you straight your finger, dragging stops.
3. When you touch the ball, you can shoot the ball if you curl you finger a lot. The ball will be shoot in the direction of the camera.
4. The board bounces the ball back.

Issues solved in this app:
1. Collision detection between the hand and the ball.
2. Drag the ball with the hand.

Hand detection in this app is 2D: within the camera frame and without distance to the camera. Therefore, simplifications are made:
1. Only index finger is detected and used in this app. When the index finger tip touches the ball in the camera, collision detected, and the ball will be dragged by finger. 
2. When the finger tip is dragging the ball in the camera, the ball moves in a plane that is parallel to the camera's x-y plane (z-axis point towards the viewer)


Issue 1 Collision detection between the hand and the ball.

The tool we have is: 
func projectPoint(_ point: SCNVector3) -> SCNVector3, which "projects a point in the world coordinate system using the receiver's current point of view and viewport".

So we can get the coordinate of the ball in the camera using this function, and the hand detection machine learning model gives us the finger's coordinate in the camera. Then the issue is equivalent to finding the radius of the ball in the camera (in pixels), which is equivalent to finding the point on the ball that is projected to the leftmost (or rightmost, topmost) point in the camera, which is equivalent to finding the direction, along which the projection moves fastest to left.

Let 
projectPoint(ball.center) = ballCenterCamera (1)
projectPoint(ball.center + iw) = ballCenterCamera + x1 * ic + y1 * jc (2)
projectPoint(ball.center + jw) = ballCenterCamera + x2 * ic + y2 * jc (3)
projectPoint(ball.center + kw) = ballCenterCamera + x3 * ic + y3 * jc (4)

where iw, jw, kw are the x, y, z axis in world coordinate system, and ic, jc are the x,y axis in camera coordinate system.

Subtract (2), (3), (4) with (1) to get rid of ballCenterCamera, which we don't care:
projectPoint(iw) =  x1 * ic + y1 * jc (5)
projectPoint(jw) =  x2 * ic + y2 * jc (6)
projectPoint(kw) =  x3 * ic + y3 * jc (7)

We only care about 1 direction in the camera frame, so let's cancel out jc from (5), (6), (7):
We will get 2 equations:
ic = projectPoint(A1 * iw + B1 * jw + C1 * kw) 
ic = projectPoint(A2 * iw + B2 * jw + C2 * kw) 
which are 2 direction along which the projection moves left/right. Ai, Bi, Ci can be easily calculated.

Our goal is to find the direction, along which the projection moves fastest to left/right, which is equivalent to:
If the projection moves 1 unit in the camera, along which direction does the ball move least?

Let 
ic = k * projectPoint(A1 * iw + B1 * jw + C1 * kw) + (1 - k) * projectPoint(A2 * iw + B2 * jw + C2 * kw) 
    =  projectPoint(f1(k) * iw + f2(k) * jw + f3(k))
where fi(k) can be easily calculated.

Take the length of the vector f1(k) ^ 2 + f2(k) ^ 2 + f3(k) ^ 2, take a derivative and you will get k.
Then take this vector and intersect it with the ball. The intersection point P is projected on the leftmost/rightmost point of the ball in the camera. projectPoint(P) gives the coordinate in the camera, and we can get the radius from the coodinates of this point and the center.

Issue 2 Drag the ball with the hand.

We have assumed that the ball moves on a plane parallel to the camera's x-y plane.

Get the vectors of the camera's x and y axis in the world coordinate system:
Let
xAxisc = x1 * iw + y1 * jw + z1 * kw
yAxisc = x2 * iw + y2 * jw + z2 * kw

Move the ball 1 unit along xAxisc and yAxisc separately, and use the projection function:
projectPoint(ball.center) = ballCenterCamera
projectPoint(ball.center + xAxisc * 1) = ballCenterCamera + x1 * ic + y1 * jc
projectPoint(ball.center + yAxisc * 1) = ballCenterCamera + x2 * ic + y2 * jc

Doing the same trick as before, we can get how the project moves when the ball moves along the camera's x and y axis.
If the finger tip moves x0 and y0 in the camera frame, we can back out how much the ball need to move along the camera's x and y axis: 2 variables, 2 equations.

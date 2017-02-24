/*
 Copyright 2016-present The Material Motion Authors. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation
import IndefiniteObservable

/** Create a core animation tween system for a Tween plan. */
public func coreAnimation(_ tween: PathTween) -> MotionObservable<CGPoint> {
  return MotionObservable(Metadata("Core Animation Path Tween", args: [tween.duration, tween.delay, tween.path, tween.timeline as Any, tween.enabled, tween.state])) { observer in

    var animationKeys: [String] = []
    var subscriptions: [Subscription] = []
    var activeAnimations = Set<String>()

    let checkAndEmit = {
      subscriptions.append(tween.path.subscribe { pathValue in
        let animation = CAKeyframeAnimation()
        animation.path = pathValue

        observer.next(pathValue.getAllPoints().last!)

        guard let duration = tween.duration._read() else {
          return
        }
        animation.beginTime = tween.delay
        animation.duration = CFTimeInterval(duration)

        let key = NSUUID().uuidString
        activeAnimations.insert(key)
        animationKeys.append(key)

        tween.state.value = .active

        if let timeline = tween.timeline {
          observer.coreAnimation?(.timeline(timeline))
        }
        observer.coreAnimation?(.add(animation, key, initialVelocity: nil, completionBlock: {
          activeAnimations.remove(key)
          if activeAnimations.count == 0 {
            tween.state.value = .atRest
          }
        }))
        animationKeys.append(key)

        let view = UIView()
        let brushLayer = CAShapeLayer()
        brushLayer.opacity = 0.5
        brushLayer.lineWidth = 2
        brushLayer.strokeStart = 0
        brushLayer.strokeEnd = 1
        brushLayer.lineCap = kCALineJoinRound
        brushLayer.fillColor = UIColor.white.withAlphaComponent(0).cgColor
        brushLayer.strokeColor = UIColor(red: 22/255.0, green: 149/255.0, blue: 242/255.0, alpha: 1).cgColor
        brushLayer.path = pathValue

        if let timeline = tween.timeline {
          if timeline.paused.value {
            brushLayer.lineDashPattern = [2, 3]
          } else {
            brushLayer.lineDashPattern = nil
            brushLayer.strokeStart = 1

            let strokeEndAnimation = CABasicAnimation(keyPath: "strokeEnd")
            strokeEndAnimation.duration = animation.duration
            strokeEndAnimation.timingFunction = animation.timingFunction
            strokeEndAnimation.fromValue = 0
            strokeEndAnimation.toValue = 1
            brushLayer.add(strokeEndAnimation, forKey: "strokeEnd")

            let strokeStartAnimation = CABasicAnimation(keyPath: "strokeStart")
            strokeStartAnimation.duration = animation.duration * 0.75
            strokeStartAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
            strokeStartAnimation.fromValue = 0
            strokeStartAnimation.toValue = 1
            strokeStartAnimation.beginTime = CACurrentMediaTime() + animation.duration * 0.75
            strokeStartAnimation.fillMode = kCAFillModeBackwards
            brushLayer.add(strokeStartAnimation, forKey: "strokeStart")

            let lineWidthAnimation = CABasicAnimation(keyPath: "lineWidth")
            lineWidthAnimation.duration = animation.duration * 1.75
            lineWidthAnimation.fromValue = 3
            lineWidthAnimation.toValue = 0
            brushLayer.add(lineWidthAnimation, forKey: "lineWidth")
          }
        }

        view.layer.addSublayer(brushLayer)
        observer.visualization?(view)
      })
    }

    let activeSubscription = tween.enabled.dedupe().subscribe { enabled in
      if enabled {
        checkAndEmit()
      } else {
        animationKeys.forEach { observer.coreAnimation?(.remove($0)) }
        activeAnimations.removeAll()
        animationKeys.removeAll()
        tween.state.value = .atRest
      }
    }

    return {
      animationKeys.forEach { observer.coreAnimation?(.remove($0)) }
      subscriptions.forEach { $0.unsubscribe() }
      activeSubscription.unsubscribe()
    }
  }
}

extension CGPath {

  // Iterates over each registered point in the CGPath. We must use @convention notation to bridge
  // between the swift and objective-c block APIs.
  // Source: http://stackoverflow.com/questions/12992462/how-to-get-the-cgpoints-of-a-cgpath#36374209
  private func forEach(body: @convention(block) (CGPathElement) -> Void) {
    typealias Body = @convention(block) (CGPathElement) -> Void
    let callback: @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CGPathElement>) -> Void = { (info, element) in
      let body = unsafeBitCast(info, to: Body.self)
      body(element.pointee)
    }
    let unsafeBody = unsafeBitCast(body, to: UnsafeMutableRawPointer.self)
    self.apply(info: unsafeBody, function: unsafeBitCast(callback, to: CGPathApplierFunction.self))
  }

  fileprivate func getAllPoints() -> [CGPoint] {
    var arrayPoints: [CGPoint] = []
    self.forEach { element in
      switch (element.type) {
      case .moveToPoint:
        arrayPoints.append(element.points[0])
      case .addLineToPoint:
        arrayPoints.append(element.points[0])
      case .addQuadCurveToPoint:
        arrayPoints.append(element.points[0])
        arrayPoints.append(element.points[1])
      case .addCurveToPoint:
        arrayPoints.append(element.points[0])
        arrayPoints.append(element.points[1])
        arrayPoints.append(element.points[2])
      default: break
      }
    }
    return arrayPoints
  }
}

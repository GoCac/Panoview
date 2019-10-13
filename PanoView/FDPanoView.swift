//
//  FDPanoView.swift
//  FDUIKit
//
//  Created by Youhao Gong 宫酉昊 on 2019/7/19.
//  Copyright © 2019 iOS Developer Zone. All rights reserved.
//

import Foundation
import SceneKit
import CoreMotion

public struct FDPanoConfiguration {
    /// 滑动速率
    public var panRate: CGFloat
    /// 缩放速率
    public var pinchRate: CGFloat
    
    /// 球半径
    internal let radius: CGFloat = 100
    /// 多边形数量类似割圆法原理
    internal let segmentCount: Int = 96
    
    /// 初始化
    ///
    /// - Parameters:
    ///   - panRate: 影响滑动手势速率，数字越小越快
    ///   - pinchRate: 影响缩放手势速率，数字越小越快
    public init(panRate: CGFloat = 5.0,
                pinchRate: CGFloat = 10.0) {
        self.panRate = panRate
        self.pinchRate = pinchRate
    }
}

public class FDPanoView: SCNView {
    private let sphere = SCNSphere() // 负责渲染图片
    private let cameraNode = SCNNode() // 负责响应陀螺仪、拖拽手势
    private let camera = SCNCamera() // 负责响应缩放手势
    
    private var configuration: FDPanoConfiguration
    
    // MARK: 初始化
    public init(frame: CGRect, image: UIImage, configuration: FDPanoConfiguration = FDPanoConfiguration()) {
        self.configuration = configuration
        super.init(frame: frame, options: nil)
        
        contentMode = .scaleToFill // 内容填充方式
        
        fixXFov(with: frame)
        
        initScene()
        createSphere()
        createCamera()
        setInitCameraForVom()
        setupCoreMotionObserver()

        sphere.firstMaterial?.diffuse.contents = image // 贴图要在 observeCoreMotion 之后渲染，否则存在一个画面闪动的问题
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // MARK: 缩放画面相关
    
    /// 初始可视区域（此时缩小到最小，只能放大）
    private var defaultXFov: Double = 100.0
    /// 最小可视区域（此时放大到最大）
    private var minXFov: Double {
        return defaultXFov * 0.75
    }
    
    private var isInitFrameChange = true
    /// 响应 frame 更新 zoom
    public override var frame: CGRect {
        didSet {
            if isInitFrameChange {
                // 第一次的 frame 变化是因为初始化 此时不需要动画
                isInitFrameChange = false
                resetZoom(animate:false)
            } else {
                resetZoom(animate:true)
            }
        }
    }
    
    private func fixXFov(with frame: CGRect) {
        // 414 / 300 的宽高比下 100 是合理的
        // 宽高比越大，需要的 xfov 也越大
        // 宽高比越小，需要的 xfov 也越小
        let benchMark = 414.0 / 300.0
        let screenRatio = Double(frame.width / frame.height)
        // 0.35 和 1.45 是根据实际测出来的最优上下限
        let scale = min(max(0.35, screenRatio / benchMark), 1.45)
        defaultXFov = 100.0 * scale
    }
    
    // MARK: public function
    
    /// 更换渲染的图片
    ///
    /// - Parameter new: 新图片
    public func setImage(_ new: UIImage) {
        sphere.firstMaterial?.diffuse.contents = new
    }
    
    /// 将镜头的缩放还原到初始值
    ///
    /// - Parameter animate: 是否需要动画
    public func resetZoom(animate: Bool = true) {
        guard camera.xFov.isEqual(to: defaultXFov) == false else {return}
        
        if animate {
            let animation = CABasicAnimation(keyPath: "xFov")
            animation.fromValue = camera.xFov
            animation.toValue = defaultXFov
            animation.duration = 0.25
            camera.addAnimation(animation, forKey: "camera-xFov")
        }
        
        // CABasicAnimation 默认会展示在 presentLayer，动画结束后就会移除掉，而 model layer 并未发生改变，需要额外设置一遍
        camera.xFov = defaultXFov
        // 需要将 lastScale 重置为初始值 1
        lastScale = 1
    }
    
    /// 放大到全屏幕
    ///
    /// 注意：为了保证显示效果放大到全屏幕是等比例的，这意味着会超过 superview 的承载区域，注意设置 layer.maskToBound = true
    ///
    /// - Parameter duration: 动画时长
    public func fullScreenDisplay(duration: TimeInterval) {
        let scale = frame.width / frame.height
        let screenRatio = UIScreen.main.bounds.size.width / UIScreen.main.bounds.size.height
        if scale >= screenRatio {
            // 宽图，放大到全屏幕后，高度与屏幕一致，宽度宽于屏幕
            let newHeight = UIScreen.main.bounds.size.height
            let newWidth = newHeight * scale
            UIView.animate(withDuration: duration) {
                self.frame = CGRect(x: -(newWidth - UIScreen.main.bounds.size.width) / 2,
                                    y: 0,
                                    width: newWidth,
                                    height: newHeight)
            }
        } else {
            // 窄图，放大到全屏幕后，宽度与屏幕一致，高度高于屏幕
            let newWidth = UIScreen.main.bounds.size.width
            let newHeight = newWidth / scale
            UIView.animate(withDuration: duration) {
                self.frame = CGRect(x: 0,
                                    y: -(newHeight - UIScreen.main.bounds.size.height) / 2,
                                    width: newWidth,
                                    height: newHeight)
            }
        }
    }
    
    // MARK: 配置 Scene
    private func initScene() {
        scene = SCNScene()
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(recognizer:)))
        addGestureRecognizer(pan)
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(recognizer:)))
        addGestureRecognizer(pinch)
    }
    
    private func createSphere() {
        // 球
        sphere.radius = configuration.radius
        sphere.segmentCount = configuration.segmentCount // 多边形数量类似割圆法原理
        sphere.firstMaterial?.isDoubleSided = false // 只渲染一面，从球体里面看，外面就不用渲染了
        sphere.firstMaterial?.cullMode = .front // 剔除外面
        sphere.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(-1, 1, 1), 1, 0, 0) // 沿y轴中心将图片旋转90度渲染，解决左右翻转问题
        
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.position = SCNVector3Make(0,0,0)
        
        scene?.rootNode.addChildNode(sphereNode)
    }
    
    private func createCamera() {
        camera.xFov = defaultXFov
        
        cameraNode.camera = camera // 负责响应陀螺仪、拖拽手势
        cameraNode.position = SCNVector3Make(0, 0, 0)
        
        scene?.rootNode.addChildNode(cameraNode)
        
        setInitCameraForVom()
    }
    
    // MARK: 陀螺仪控制摄像机
    private let motionManager = CMMotionManager() // 监听陀螺仪数据
    private func setupCoreMotionObserver() {
        guard motionManager.isDeviceMotionAvailable else {
//            fatalError("设备没有陀螺仪")
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        startObserve()
    }
    
    private func startObserve() {
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main, withHandler: {
            [weak self] (motion, error) in
            guard let motion = motion else { return }
            guard let weakSelf = self else { return }
            let currentAttitude = motion.attitude;
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            let quaternion = weakSelf.orientationFrom(cmQuaternion: currentAttitude.quaternion)
            weakSelf.cameraNode.orientation = weakSelf.calAddPanRotation(quaternion)
            SCNTransaction.commit()
        })
    }
    
    private func orientationFrom(cmQuaternion q: CMQuaternion) -> GLKQuaternion {
        let gq1 =  GLKQuaternionMakeWithAngleAndAxis(GLKMathDegreesToRadians(-90), 1, 0, 0) // add a rotation of the pitch 90 degrees
        let gq2 =  GLKQuaternionMake(Float(q.x), Float(q.y), Float(q.z), Float(q.w)) // the current orientation
        let qp  =  GLKQuaternionMultiply(gq1, gq2); // get the "new" orientation
        return qp
    }
    
    // MARK: 拖拽手势控制摄像机
    private var offsetY: CGFloat = 0
    private var offsetX: CGFloat = 0
    
    private var lastX: CGFloat = 0
    private var lastY: CGFloat = 0
    @objc
    private func didPan(recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .changed || recognizer.state == .began {
            let translatedPoint = recognizer.translation(in: recognizer.view)
            offsetY += (translatedPoint.y - lastY)
            offsetX += (translatedPoint.x - lastX)
            lastX = translatedPoint.x
            lastY = translatedPoint.y
        }
        if recognizer.state == .ended {
            lastX = 0
            lastY = 0
        }
    }
    
    /// 目前给定的图片默认的朝向是后方，需要加一个初始偏移值，TODO: 更优雅的方案
    private func setInitCameraForVom() {
        offsetY = 55.5 // 修正初始值，保证对准图片正中间
        offsetX = 906.0 // 修正初始值，保证对准图片正中间
    }
    
    /// 给四元素添加上滑动手势积累的旋转
    ///
    /// - Parameter glQuaternion: 原四元素（直接从陀螺仪拿到的数据）
    /// - Returns: 滑动手势作用后的四元素
    private func calAddPanRotation(_ glQuaternion: GLKQuaternion) -> SCNQuaternion {
        var result = glQuaternion
        
        let yRadians = Float(offsetY / configuration.panRate).radians
        let xRadians = Float(offsetX / configuration.panRate).radians
        
        // 上下
        let yMultiplier = GLKQuaternionMakeWithAngleAndAxis(yRadians, 1, 0, 0)
        result = GLKQuaternionMultiply(glQuaternion, yMultiplier)
        
        // 左右
        let xMultiplier = GLKQuaternionMakeWithAngleAndAxis(xRadians, 0, 1, 0)
        result = GLKQuaternionMultiply(xMultiplier, result)
        
        return SCNQuaternion(x: result.x,
                             y: result.y,
                             z: result.z,
                             w: result.w)
    }
    
    // MARK: 缩放手势控制摄像机
    
    // scale 的变化是非线性的：Pinch 在双指放大时，scale 从 1 开始变大，iPhoneX 的对角线的距离 scale 可以到 7 左右；当手指离开屏幕再双指缩小时，scale 从 1 开始变小，最小值为 0。
    // 为了保证缩放速率的稳定，这里使用的解决方案是记录上次 pinch 结束时的 scale，下次继续基于这个值进行放大缩小。
    // resetZoom 方法需要将 lastScale 重置为初始值 1
    private var lastScale: CGFloat = 1
    @objc
    private func didPinch(recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .began {
            recognizer.scale = lastScale
        }
        if recognizer.state == .changed {
            let pinchVelocity = recognizer.velocity
            // 计算新的缩放值
            let newXFov = camera.xFov - Double (pinchVelocity / configuration.pinchRate)
            // 值有效时才进行赋值、记录操作
            if newXFov <= defaultXFov,
                newXFov >= minXFov {
                camera.xFov = newXFov
                lastScale = recognizer.scale < 1 ? 1 : recognizer.scale
            }
        }
    }
}

fileprivate extension Float {
    var radians: Float {
        return self * .pi / 180
    }
}

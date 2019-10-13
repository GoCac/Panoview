import UIKit

class ViewController: UIViewController {
    var sceneView: FDPanoView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .gray
        
        let button = UIButton(frame: CGRect(x: 25, y: 100, width: 100, height: 30))
        button.setTitle("复位缩放", for: .normal)
        button.addTarget(self, action: #selector(resetZoom), for: .touchUpInside)
        view.addSubview(button)
        
        let button1 = UIButton(frame: CGRect(x: 25, y: 140, width: 100, height: 30))
        button1.setTitle("换图 1", for: .normal)
        button1.addTarget(self, action: #selector(setImage1), for: .touchUpInside)
        view.addSubview(button1)
        
        let button2 = UIButton(frame: CGRect(x: 25, y: 180, width: 100, height: 30))
        button2.setTitle("换图 2", for: .normal)
        button2.addTarget(self, action: #selector(setImage2), for: .touchUpInside)
        view.addSubview(button2)
        
        let button3 = UIButton(frame: CGRect(x: 25, y: 220, width: 100, height: 30))
        button3.setTitle("关闭全景图", for: .normal)
        button3.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(button3)
        
        let button4 = UIButton(frame: CGRect(x: 25, y: 260, width: 100, height: 30))
        button4.setTitle("打开全景图", for: .normal)
        button4.addTarget(self, action: #selector(open), for: .touchUpInside)
        view.addSubview(button4)
        
        open()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    @objc
    func resetZoom() {
        sceneView?.resetZoom(animate: true)
    }
    
    var imageList: [UIImage] = []
    
    @objc
    func setImage1() {
        sceneView?.setImage(imageList[0])
    }
    
    @objc
    func setImage2() {
        sceneView?.setImage(imageList[1])
    }
    
    @objc
    func open() {
        if sceneView != nil {return}
        
        let imagePath = Bundle.main.path(forResource: "image0", ofType: "jpg")!
        
        let config = FDPanoConfiguration()
        let sceneView = FDPanoView(frame: CGRect(x: 0,
                                                 y: 300,
                                                 width: UIScreen.main.bounds.width,
                                                 height: 300),
                                   image: UIImage(contentsOfFile:imagePath)!,
                                   configuration: config)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapGLView))
        sceneView.addGestureRecognizer(tap)
        view.insertSubview(sceneView, at: 0)
        self.sceneView = sceneView
        
        DispatchQueue.global().async { [weak self] in
            guard let weakSelf = self else {return}
            if let imagePath = Bundle.main.path(forResource: "image1", ofType: "jpg"),
                let image = UIImage(contentsOfFile:imagePath) {
                weakSelf.imageList.append(image.decompress())
            }
            if let imagePath = Bundle.main.path(forResource: "image2", ofType: "jpg"),
                let image = UIImage(contentsOfFile:imagePath) {
                weakSelf.imageList.append(image.decompress())
            }
        }
    }
    
    @objc
    func close() {
        sceneView?.removeFromSuperview()
        sceneView = nil
        
        imageList.removeAll()
    }
    
    var isOpen = false
    @objc
    func didTapGLView() {
        if isOpen {
            isOpen = false
            UIView.animate(withDuration: 0.5) {
                self.sceneView?.frame = CGRect(x: 0,
                                               y: 300,
                                               width: UIScreen.main.bounds.width,
                                               height: 300)
            }
        } else {
            isOpen = true
            sceneView?.fullScreenDisplay(duration: 0.5)
        }
    }
}


// MARK: 强制解压缩成位图
fileprivate extension UIImage {
    /// 强制解压缩成位图
    ///
    /// - Returns: 解压缩得到的位图
    func decompress() -> UIImage {
        guard let cgImage = self.cgImage,
            let decodedCGImage = cgImage.createDecodedCopy() else {
                return self
        }
        let decompressedImage = UIImage(cgImage: decodedCGImage, scale: self.scale, orientation: self.imageOrientation)
        return decompressedImage
    }
}

fileprivate extension CGImage {
    /// 绘制解压缩 CGImage（强制解压缩成位图）
    ///
    /// - Returns: 解压缩后得到的位图
    func createDecodedCopy() -> CGImage? {
        let width = self.width
        let height = self.height
        
        let alphaInfo = CGImageAlphaInfo(rawValue: self.alphaInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        var hasAlpha = false
        if (alphaInfo == CGImageAlphaInfo.premultipliedLast ||
            alphaInfo == CGImageAlphaInfo.premultipliedFirst ||
            alphaInfo == CGImageAlphaInfo.last ||
            alphaInfo == CGImageAlphaInfo.first) {
            hasAlpha = true
        }
        // BGRA8888 (premultiplied) or BGRX8888
        // same as UIGraphicsBeginImageContext() and -[UIView drawRect:]
        var bitmapInfo = CGBitmapInfo.byteOrder32Host
        bitmapInfo = CGBitmapInfo(rawValue: bitmapInfo.rawValue | (hasAlpha ? CGImageAlphaInfo.premultipliedFirst.rawValue : CGImageAlphaInfo.noneSkipFirst.rawValue))
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo.rawValue) else {
                                        return nil
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }
}

fileprivate extension CGBitmapInfo {
    static var byteOrder32Host: CGBitmapInfo {
        return CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue) ? .byteOrder32Little : .byteOrder32Big
    }
}

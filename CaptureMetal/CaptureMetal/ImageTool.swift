//
//  ImageTool.swift
//  CaptureMetal
//
//  Created by dzq_mac on 2020/7/26.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit

class ImageTool: NSObject {

    class func setUpImageTexture(imageName:String,device:MTLDevice,loadTga:Bool = false) ->MTLTexture? {
        var imageSoruce = UIImage(named: imageName)
        if loadTga {
            let url = Bundle.main.url(forResource: "Image", withExtension: "tga")
            imageSoruce = ImageTool.tgaTOImage(url: url!)
        }
        
        guard let image = imageSoruce?.cgImage else {
            return nil
        }
        
        let width = image.width
        let height = image.height
        
        //开辟内存，绘制到这个内存上去
        let spriteData: UnsafeMutablePointer = UnsafeMutablePointer<GLubyte>.allocate(capacity: MemoryLayout<GLubyte>.size * width * height * 4)
        UIGraphicsBeginImageContext(CGSize(width: width, height: height))
        //获取context
        let spriteContext = CGContext(data: spriteData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: image.colorSpace!, bitmapInfo: image.bitmapInfo.rawValue)
        spriteContext?.translateBy(x:0 , y: CGFloat(height))
        spriteContext?.scaleBy(x: 1, y: -1)
        spriteContext?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        UIGraphicsEndImageContext()
        
        //        spriteData
        
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba8Unorm //MTLPixelFormatRGBA8Unorm defoat
        textureDescriptor.width = image.width
        textureDescriptor.height = image.height
        let texture = device.makeTexture(descriptor: textureDescriptor)
        
        texture?.replace(region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: image.width, height: image.height, depth: 1)), mipmapLevel: 0, withBytes: spriteData, bytesPerRow: 4 * image.width)
        
        free(spriteData)
        return texture
    }
    class func tgaTOImage(url:URL) -> UIImage? {
        if url.pathExtension.caseInsensitiveCompare("tga") != .orderedSame {
            return nil
        }
        guard let fileData = try? Data.init(contentsOf: url) else {
            print("打开tga文件失败！")
            return nil
        }
        let image = UIImage(data: fileData)
        return image
    }
}

extension UIView {
    //将当前视图转为UIImage
    func asImage() -> UIImage? {
        if #available(iOS 10.0, *) {
            let renderer = UIGraphicsImageRenderer(bounds: bounds)
            return renderer.image { rendererContext in
                layer.render(in: rendererContext.cgContext)
            }
        } else {
            return nil
        }
    }
}

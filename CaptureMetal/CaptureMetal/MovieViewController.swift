//
//  MovieViewController.swift
//  CaptureMetal
//
//  Created by dzq_mac on 2020/7/12.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import AVFoundation
import MetalKit
import MetalPerformanceShaders

struct ConvertMatrix {
    var matrix :float3x3
    var verctor :SIMD3<Float>
    
}

class MovieViewController: UIViewController {

   
    var device :MTLDevice!
    var mtkView : MTKView!
    
    var reader: DQAssetReader?
    
    var texture : MTLTexture?
    var textureUV:MTLTexture?
    
    var tetureCache : CVMetalTextureCache?
    
    var state : MTLRenderPipelineState?
    var commendQueue: MTLCommandQueue?
    
    var vertexbuffer :MTLBuffer?
    var cmatrixBuffer :MTLBuffer?
    
    var useYUV = true
    
    var timeRange : CMTimeRange?
    
    var pauseButton:UIButton!
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "movie"
        self.view.backgroundColor = .white
        
        let path = Bundle.main.path(forResource: "123", ofType: "mp4")
        let url1 = URL(fileURLWithPath: path!)
        
        reader = DQAssetReader(url: url1,valueYUV: useYUV)
        reader?.timeRange = CMTimeRange(start: CMTime(value: 2, timescale: 1, flags: CMTimeFlags(rawValue: 1), epoch: 0), duration: CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 5), epoch: 0))
        setMetalConfig()
        vertexData()
        yuvToRGBmatrix()
        
        pauseButton = UIButton(frame: CGRect(x: 0, y: view.frame.size.height - 100, width: 100, height: 50))
        pauseButton.center.x = view.center.x
        
        pauseButton.setTitle("暂停", for:.normal)
        pauseButton.setTitle("继续", for:.selected)
        pauseButton.backgroundColor = .gray
        view.addSubview(pauseButton)
        pauseButton.addTarget(self, action: #selector(pauseAction(btn:)), for: .touchUpInside)
        
    }
    
    @objc func pauseAction(btn:UIButton){
        btn.isSelected = !btn.isSelected
        
        if !btn.isSelected {
            if reader?.readBuffer() == nil {
                reader?.setUpAsset()
                pauseButton.setTitle("继续", for:.selected)
            }
        }
    }
    
    func setMetalConfig()  {
        guard let device1 = MTLCreateSystemDefaultDevice() else{
            return
        }
        self.device = device1
        mtkView = MTKView(frame: view.bounds, device: device)
        
        mtkView.delegate = self
        
        mtkView.framebufferOnly = false
        
        //创建纹理缓存区
        CVMetalTextureCacheCreate(nil, nil, device1, nil, &tetureCache)
        
        view.addSubview(mtkView)
        let library = device.makeDefaultLibrary()
        let verFunc = library?.makeFunction(name: "vertexShader")
        let fragFunc = library?.makeFunction(name: "samplingShader")
        
        let descriptor =  MTLRenderPipelineDescriptor()
        descriptor.fragmentFunction = fragFunc
        descriptor.vertexFunction = verFunc
        descriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        state = try? device.makeRenderPipelineState(descriptor: descriptor)
        
        commendQueue = device.makeCommandQueue()
        
    }

    func vertexData() {
        var vertex:[Float] = [
             1.0, -1.0, 0.0, 1.0,  1.0, 1.0,1.0,1.0,
            -1.0, -1.0, 0.0, 1.0,  0.0, 1.0,1.0,1.0,
            -1.0,  1.0, 0.0, 1.0,  0.0, 0.0,1.0,1.0,
             1.0, -1.0, 0.0, 1.0,  1.0, 1.0,1.0,1.0,
            -1.0,  1.0, 0.0, 1.0,  0.0, 0.0,1.0,1.0,
             1.0,  1.0, 0.0, 1.0,  1.0, 0.0,1.0,1.0
        ]
        
        vertexbuffer = device.makeBuffer(bytes: &vertex, length: MemoryLayout<Float>.size * vertex.count, options: MTLResourceOptions.storageModeShared)
    }
    
    func changeVertex(sampleBuffer:CMSampleBuffer) {
        
            var vertexs:[Float] = [
                1.0, -1.0, 0.0, 1.0,  1.0, 1.0,1.0,1.0,
               -1.0, -1.0, 0.0, 1.0,  0.0, 1.0,1.0,1.0,
               -1.0,  1.0, 0.0, 1.0,  0.0, 0.0,1.0,1.0,
                1.0, -1.0, 0.0, 1.0,  1.0, 1.0,1.0,1.0,
               -1.0,  1.0, 0.0, 1.0,  0.0, 0.0,1.0,1.0,
                1.0,  1.0, 0.0, 1.0,  1.0, 0.0,1.0,1.0
            ]
            
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
                   
            let scaleF = CGFloat(view.frame.height)/CGFloat(view.frame.width)
            let scaleI = CGFloat(height)/CGFloat(width)
                       
            let imageScale = scaleF>scaleI ? (1,scaleI/scaleF) : (scaleF/scaleI,1)
            
            for (i,v) in vertexs.enumerated(){
                if i % 8 == 0 {
                    vertexs[i] = v * Float(imageScale.0)
                }
                if i % 8 == 1{
                    vertexs[i] = v * Float(imageScale.1)
                }

            }
        
            vertexbuffer = device.makeBuffer(bytes: vertexs, length: MemoryLayout<Float>.size * vertexs.count, options: MTLResourceOptions.storageModeShared)
        
    }
    
    func yuvToRGBmatrix() {
        
        /*
        YUV与RGB相互转化公式
         传输时使用YUV节省空间大小
         4:4:4  YUV全部取值。        不节省空间
         4:2:2  U/V隔一个取一个。     节省1/3
         4:2:0  第一行取U，第二行取V，还是隔一个取一个   节省1/2
         
         Y = 0.299 * R + 0.587 * G + 0.114 * B
         U = -0.174 * R - 0.289 * G + 0.436 * B
         V = 0.615 * R - 0.515 * G - 0.100 * B
         
         
         R = Y + 1.14 V
         G = Y - 0.390 * U - 0.58 * V
         B = Y + 2.03 * U
         */
        
        //1.转化矩阵
        // BT.601, which is the standard for SDTV.
        let kColorConversion601DefaultMatrix = float3x3(
            SIMD3<Float>(1.164,1.164, 1.164),
            SIMD3<Float>(0.0, -0.392, 2.017),
            SIMD3<Float>(1.596, -0.813, 0.0))
        
        // BT.601 full range
        let kColorConversion601FullRangeMatrix = float3x3(
            SIMD3<Float>(1.0,    1.0,    1.0),
            SIMD3<Float>(0.0,  -0.343, 1.765),
            SIMD3<Float>(1.4,    -0.711, 0.0))
        
        // BT.709, which is the standard for HDTV.
        let kColorConversion709DefaultMatrix = float3x3(
            SIMD3<Float>(1.164, 1.164, 1.164),
            SIMD3<Float>(0.0,  -0.213, 2.112),
            SIMD3<Float>(1.793, -0.533,  0.0))
        
        //
        
        let offset = SIMD3<Float>(-(16.0/255.0), -0.5, -0.5)
        
        var cMatrix = ConvertMatrix(matrix: kColorConversion601FullRangeMatrix, verctor: offset)
        
        self.cmatrixBuffer = device.makeBuffer(bytes: &cMatrix, length: MemoryLayout<ConvertMatrix>.size, options: .storageModeShared)
        
        
    }

}

extension MovieViewController:MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    
    func draw(in view: MTKView) {
        
        if pauseButton.isSelected  {
            return
        }
        guard let commandBuffer = commendQueue?.makeCommandBuffer() else {
            return
        }
        //texture
        guard let sample = self.reader?.readBuffer() else {
            pauseButton.isSelected = true
            pauseButton.setTitle("重播", for: UIControl.State.selected)
            return
            
        }
        
        //encode
        guard let passDescriptor = view.currentRenderPassDescriptor else{return}
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.3, 0.1, 0.4, 1)
        guard let encode = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else{return}
        guard let pipeState = self.state else {return}
        encode.setRenderPipelineState(pipeState)
        encode.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(view.drawableSize.width), height: Double(view.drawableSize.height), znear: -1, zfar: 1))
        
        
        changeVertex(sampleBuffer: sample)
        encode.setVertexBuffer(vertexbuffer, offset: 0, index: 0)
        encode.setFragmentBuffer(cmatrixBuffer, offset: 0, index: 0)
        setTextureWithEncoder(encoder: encode,sampleBuffer: sample,yuv: useYUV)
        
        if let blendTex = ImageTool.setUpImageTexture(imageName: "image.jpg", device: device) {
            encode.setFragmentTexture(blendTex, index: 2)
        }
    
        encode.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encode.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
        self.texture = nil
    }
    
    func setTextureWithEncoder(encoder:MTLRenderCommandEncoder,sampleBuffer:CMSampleBuffer,yuv:Bool = false) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        func settexture(index:Int){
            var pixelFormat:MTLPixelFormat = .bgra8Unorm
            
            if index == -1{
                pixelFormat = .bgra8Unorm
            }else if index == 0{
                pixelFormat = .r8Unorm
            }else if index == 1{
                pixelFormat = .rg8Unorm
            }
            var metalTexture:CVImageBuffer?
            let width =  CVPixelBufferGetWidthOfPlane(imageBuffer, index == -1 ? 0 : index)
            let hieght = CVPixelBufferGetHeightOfPlane(imageBuffer, index == -1 ? 0 : index)
            let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                   self.tetureCache!,
                                                                   imageBuffer,
                                                                   nil,
                                                                   pixelFormat,
                                                                   width,
                                                                   hieght,
                                                                   index == -1 ? 0 : index,
                                                                   &metalTexture)
            if  status == kCVReturnSuccess{
                if index == 1 {
                    self.textureUV = CVMetalTextureGetTexture(metalTexture!)
                    encoder.setFragmentTexture(self.textureUV, index: 1)
                }else{
                    self.texture = CVMetalTextureGetTexture(metalTexture!)
                    encoder.setFragmentTexture(self.texture, index: 0)
                }
                
                
            }
        }
        
        if yuv {
            
            settexture(index: 0)
            settexture(index: 1)
        }else{
            settexture(index: -1)
        }
        
        
    }
    
}


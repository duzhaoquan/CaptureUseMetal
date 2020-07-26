//
//  ViewController.swift
//  CaptureMetal
//
//  Created by dzq_mac on 2020/7/9.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation
import MetalKit
import Metal
import MetalPerformanceShaders

class ViewController: UIViewController {

    //按钮
    var captureButton:UIButton!
    var recodButton:UIButton!
    
    var session : AVCaptureSession = AVCaptureSession()
    var queue = DispatchQueue(label: "quque")
    var input: AVCaptureDeviceInput?
    lazy var previewLayer  = AVCaptureVideoPreviewLayer(session: self.session)
    lazy var recordOutput = AVCaptureMovieFileOutput()
    
    //Metal相关
    var device :MTLDevice!
    var mtkView : MTKView!
    
    var texture : MTLTexture?
    
    var tetureCache : CVMetalTextureCache?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        captureButton = UIButton(frame: CGRect(x: 10, y: view.bounds.size.height - 60, width: 150, height: 50))
        captureButton.backgroundColor = .gray
        captureButton.setTitle("start capture", for: .normal)
        captureButton.addTarget(self, action: #selector(capture(btn:)), for: .touchUpInside)
        view.addSubview(captureButton)
        
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.backgroundColor = .gray

        recodButton.setTitle("paly movie", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
        
        
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
    }

    @objc func recordAction(btn:UIButton){
        btn.isSelected = !btn.isSelected
        if session.isRunning {
            if btn.isSelected {
                btn.setTitle("stop record", for: .normal)
                
                if !session.isRunning{
                    session.startRunning()
                }
                if session.canAddOutput(recordOutput){
                    session.addOutput(recordOutput)
                }
//                recordOutput.
                let connection = recordOutput.connection(with: .video)
                connection?.preferredVideoStabilizationMode = .auto
                
                guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return  }
                let url = URL(fileURLWithPath: "\(path)/test.mp4")
                recordOutput.startRecording(to: url, recordingDelegate: self)
                
                
            }else{
                btn.setTitle("start record", for: .normal)
                
                recordOutput.stopRecording()
                
            }
        }else{
//            btn.setTitle("paly movie", for: .normal)
            let moVC = MovieViewController()
            self.navigationController?.pushViewController(moVC, animated: true)
        }
        
    }
    @objc func capture(btn:UIButton){
        btn.isSelected = !btn.isSelected
        
        if btn.isSelected {
//            recodButton.isHidden = false
            recodButton.setTitle("start record", for: .normal)
            btn.setTitle("stop capture", for: UIControl.State.normal)
            guard let device = getCamera(postion: .back) else{
                return
            }
            
            guard let input = try? AVCaptureDeviceInput(device: device) else{
                return
            }
            self.input = input
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output){
                session.addOutput(output)
            }
            //这里设置格式为BGRA，而不用YUV的颜色空间，避免使用Shader转换
            //注意:这里必须和后面CVMetalTextureCacheCreateTextureFromImage 保存图像像素存储格式保持一致.否则视频会出现异常现象.
            output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey)  :NSNumber(value: kCVPixelFormatType_32BGRA) ]
            let connection: AVCaptureConnection = output.connection(with: .video)!
            connection.videoOrientation = .portrait
//            previewLayer.frame = view.bounds
//            view.layer.insertSublayer(previewLayer, at: 0)
            setMetalConfig()
            view.insertSubview(mtkView, at: 0)
            session.startRunning()
        }else{
//            recodButton.isHidden = true
            btn.setTitle("start capture", for: .normal)
            if recordOutput.isRecording {
                recordOutput.stopRecording()
            }
            recodButton.isSelected = false
            recodButton.setTitle("play movie", for: .normal)
            session.stopRunning()
//            previewLayer.removeFromSuperlayer()
            mtkView.removeFromSuperview()
        }
        
        
        
    }
    //获取相机设备
    func getCamera(postion: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var devices = [AVCaptureDevice]()
        
        if #available(iOS 10.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera], mediaType: AVMediaType.video, position: AVCaptureDevice.Position.unspecified)
            devices = discoverySession.devices
        } else {
            devices = AVCaptureDevice.devices(for: AVMediaType.video)
        }
        
        for device in devices {
            if device.position == postion {
                return device
            }
        }
        return nil
    }
    //切换摄像头
    func swapFrontAndBackCameras() {
        if let input = input {
            
            var newDevice: AVCaptureDevice?
            
            if input.device.position == .front {
                newDevice = getCamera(postion: AVCaptureDevice.Position.back)
            } else {
                newDevice = getCamera(postion: AVCaptureDevice.Position.front)
            }
            
            if let new = newDevice {
                do{
                    let newInput = try AVCaptureDeviceInput(device: new)
                    
                    session.beginConfiguration()
                    
                    session.removeInput(input)
                    session.addInput(newInput)
                    self.input = newInput
                    
                    session.commitConfiguration()
                }
                catch let error as NSError {
                    print("AVCaptureDeviceInput(): \(error)")
                }
            }
        }
    }
    //设置横竖屏问题
    func setupVideoPreviewLayerOrientation() {
        
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            if #available(iOS 13.0, *) {
                if let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation{
                    switch orientation {
                    case .portrait:
                        connection.videoOrientation = .portrait
                    case .landscapeLeft:
                        connection.videoOrientation = .landscapeLeft
                    case .landscapeRight:
                        connection.videoOrientation = .landscapeRight
                    case .portraitUpsideDown:
                        connection.videoOrientation = .portraitUpsideDown
                    default:
                        connection.videoOrientation = .portrait
                    }
                }
            }else{
                switch UIApplication.shared.statusBarOrientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .landscapeRight:
                    connection.videoOrientation = .landscapeRight
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeLeft
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                default:
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureFileOutputRecordingDelegate,MTKViewDelegate {
    //mtk
    func draw(in view: MTKView) {
        
        guard let queue = device.makeCommandQueue() else { return }
        guard let buffer = queue.makeCommandBuffer() else { return }
//        guard let descriptor = mtkView.currentRenderPassDescriptor else{return}
//        guard let encode = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
//            return
//        }
        //metal有许多内置滤镜 MetalPerformanceShaders
        let blurFilter = MPSImageGaussianBlur.init(device: device, sigma: 10)
        guard let texture = self.texture else {
            return
        }
        
        blurFilter.encode(commandBuffer: buffer, sourceTexture: texture, destinationTexture: view.currentDrawable!.texture)
        
        buffer.present(view.currentDrawable!)
        buffer.commit()
        self.texture = nil
        
        
        
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    //录制完成
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
    }
    //采集结果
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return  }
//        imageBuffer.attachments[0].
        var metalTexture:CVMetalTexture?
        
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  self.tetureCache!,
                                                  imageBuffer,
                                                  nil,
                                                  MTLPixelFormat.bgra8Unorm,
                                                  CVPixelBufferGetWidth(imageBuffer),
                                                  CVPixelBufferGetHeight(imageBuffer),
                                                  0,
                                                  &metalTexture)
        if  status == kCVReturnSuccess {
            mtkView.drawableSize = CGSize(width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
            self.texture = CVMetalTextureGetTexture(metalTexture!)
            
            
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
    }
    
}


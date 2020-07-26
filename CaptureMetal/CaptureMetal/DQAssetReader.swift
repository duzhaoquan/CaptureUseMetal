//
//  DQAssetReader.swift
//  CaptureMetal
//
//  Created by dzq_mac on 2020/7/17.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import AVFoundation

/**
 *  线程加锁
 *  - lock: 加锁对象
 *  - dispose: 执行闭包函数,
 */
func synchronized(_ lock: AnyObject,dispose: ()->()) {
    objc_sync_enter(lock)
    dispose()
    objc_sync_exit(lock)
}

/// 读取视频 逐帧获取每帧
class DQAssetReader: NSObject {
    
    var readerVideoTrackOutput:AVAssetReaderTrackOutput?
    
    var assetReader:AVAssetReader!
    
    var lockObjc = NSObject()
    
    var videoUrl:URL
    var inputAsset :AVAsset!
    var YUV : Bool = false
    var timeRange:CMTimeRange?
    var loop: Bool = false
    
    init(url:URL,valueYUV:Bool = false) {
        videoUrl = url
        YUV = valueYUV
        super.init()
        setUpAsset()
    }
    
    func setUpAsset(startRead:Bool = true) {
        //创建AVUrlAsset，用于从本地/远程URL初始化资源
        //AVURLAssetPreferPreciseDurationAndTimingKey 默认为NO,YES表示提供精确的时长
        inputAsset = AVURLAsset(url: videoUrl, options: [AVURLAssetPreferPreciseDurationAndTimingKey:true])
        
        //对资源所需的键执行标准的异步载入操作,这样就可以访问资源的tracks属性时,就不会受到阻碍.
        inputAsset.loadValuesAsynchronously(forKeys: ["tracks"]) {[weak self] in
            
            guard let `self` = self else{
                return
            }
            
           //开辟子线程并发队列异步函数来处理读取的inputAsset
            DispatchQueue.global().async {[weak self] in
                
                guard let `self` = self else{
                    return
                }
                
                var error: NSError?
                let tracksStatus = self.inputAsset.statusOfValue(forKey: "tracks", error: &error)
                //如果状态不等于成功加载,则返回并打印错误信息
                if tracksStatus != .loaded{
                    
                    print(error?.description as Any)
                    return
                }
                self.processAsset(asset: self.inputAsset,startRead: startRead)
                
            }
            
            
        }
        
    }
    
    func processAsset(asset:AVAsset,startRead:Bool = true) {
        //加锁
        objc_sync_enter(lockObjc)
        
        //创建AVAssetReader
        guard let assetReader1 = try? AVAssetReader(asset: asset) else {
            return
        }
        assetReader = assetReader1
        //
        /*
         2.kCVPixelBufferPixelFormatTypeKey 像素格式.
         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : 420v(YUV)
         kCVPixelFormatType_32BGRA : iOS在内部进行YUV至BGRA格式转换
         3. 设置readerVideoTrackOutput
         assetReaderTrackOutputWithTrack:(AVAssetTrack *)track outputSettings:(nullable NSDictionary<NSString *, id> *)outputSettings
         参数1: 表示读取资源中什么信息
         参数2: 视频参数
         */
        let pixelFormat = YUV ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : kCVPixelFormatType_32BGRA
        
        readerVideoTrackOutput = AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .video).first!, outputSettings:[String(kCVPixelBufferPixelFormatTypeKey) :NSNumber(value: pixelFormat)])
        //alwaysCopiesSampleData : 表示缓存区的数据输出之前是否会被复制.YES:输出总是从缓存区提供复制的数据,你可以自由的修改这些缓存区数据The default value is YES.
        readerVideoTrackOutput?.alwaysCopiesSampleData = false
        
        
        if assetReader.canAdd(readerVideoTrackOutput!){
            assetReader.add(readerVideoTrackOutput!)
        }
        
        //开始读取
        if startRead {
            if assetReader.startReading() == false {
                print("reading file error")
            }
        }
        
        //解锁
        objc_sync_exit(lockObjc)
        
    }
    
    //读取
    func readBuffer() -> CMSampleBuffer? {
        
        objc_sync_enter(lockObjc)
        var sampleBuffer:CMSampleBuffer?
        
        
        if let readerTrackout = self.readerVideoTrackOutput  {
            sampleBuffer = readerTrackout.copyNextSampleBuffer()
        }
        
        //判断assetReader 并且status 是已经完成读取 则重新清空readerVideoTrackOutput/assetReader.并重新初始化它们
        if assetReader != nil,assetReader.status == .completed {
            readerVideoTrackOutput = nil
            assetReader = nil
            if loop {
                self.setUpAsset()
            }
        }
//        print(sampleBuffer?.presentationTimeStamp.value as Any)
        objc_sync_exit(lockObjc)
        return sampleBuffer
    }
    
    
    
}

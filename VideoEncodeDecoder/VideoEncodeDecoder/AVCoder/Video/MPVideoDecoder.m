//
//  AVVideoDecoder.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPVideoDecoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface MPVideoDecoder ()

@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@property (nonatomic, strong) dispatch_queue_t callbackQueue;
/**解码会话*/
@property (nonatomic) VTDecompressionSessionRef decodeSession;

@end

@implementation MPVideoDecoder
{
    uint8_t *_sps;
    NSUInteger _spsSize;
    uint8_t *_pps;
    NSUInteger _ppsSize;
    CMVideoFormatDescriptionRef _decodeDesc;
}

- (instancetype)initWithConfig:(MPVideoConfig *)config
{
    self = [super init];
    _config = config;
    // 创建队列
    _decodeQueue = dispatch_queue_create("h264.decode.queue", DISPATCH_QUEUE_SERIAL);
    _callbackQueue = dispatch_queue_create("h264.callback.queue", DISPATCH_QUEUE_SERIAL);
    return self;
}

/// 开始编码
- (void)decodeNaluData: (NSData *)data
{
    dispatch_async(self.decodeQueue, ^{
        uint8_t *nalu = (uint8_t *)data.bytes;
        [self decodeNaluData:nalu size:(uint32_t)data.length];
    });
}

// MARK: - Private
- (void)decodeNaluData:(uint8_t *)frame size:(uint32_t)size {
    //数据类型:frame的前4个字节是NALU数据的开始码，也就是00 00 00 01，
    // 第5个字节是表示数据类型，转为10进制后，7是sps, 8是pps, 5是IDR（I帧）信息
    int type = (frame[4] & 0x1F);
    
    // 将NALU的开始码转为4字节大端NALU的长度信息
    uint32_t naluSize = size - 4;
    uint8_t *pNaluSize = (uint8_t *)(&naluSize);
    CVPixelBufferRef pixelBuffer = NULL;
    frame[0] = *(pNaluSize + 3);
    frame[1] = *(pNaluSize + 2);
    frame[2] = *(pNaluSize + 1);
    frame[3] = *(pNaluSize);
    
    //第一次解析时: 初始化解码器initDecoder
    /*
     关键帧/其他帧数据: 调用[self decode:frame withSize:size] 方法
     sps/pps数据:则将sps/pps数据赋值到_sps/_pps中.
     */
    switch (type) {
        case 0x05: //关键帧
            if ([self initDecoder]) {
                pixelBuffer= [self decode:frame withSize:size];
            }
            break;
        case 0x06:
            //NSLog(@"SEI");//增强信息
            break;
        case 0x07: //sps
            _spsSize = naluSize;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        case 0x08: //pps
            _ppsSize = naluSize;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        default: //其他帧（1-5）
            if ([self initDecoder]) {
                pixelBuffer = [self decode:frame withSize:size];
            }
            break;
    }
}

/// 初始化Decode Session
- (BOOL)initDecoder
{
    if (_decodeSession)
        return YES;
    const uint8_t * const parameterSetPointers[2] = {_sps, _pps};
    const size_t parameterSetSizes[2] = {_spsSize, _ppsSize};
    int headerLength = 4;
    OSStatus status =  CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, parameterSetPointers, parameterSetSizes, headerLength, &_decodeDesc);
    if (status != noErr) {
        NSLog(@"Crate Decode Session Desc Failed");
        return NO;
    }
    NSDictionary *destinationPixBufferAttrs =
    @{
      (id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange], //iOS上 nv12(uvuv排布) 而不是nv21（vuvu排布）
      (id)kCVPixelBufferWidthKey: [NSNumber numberWithInteger:_config.width],
      (id)kCVPixelBufferHeightKey: [NSNumber numberWithInteger:_config.height],
      (id)kCVPixelBufferOpenGLCompatibilityKey: [NSNumber numberWithBool:true]
      };
    VTDecompressionOutputCallbackRecord callbackRecord;
    callbackRecord.decompressionOutputCallback = decompressionCallback;
    callbackRecord.decompressionOutputRefCon = (__bridge void *)self;
    status = VTDecompressionSessionCreate(NULL, _decodeDesc, NULL, (__bridge CFDictionaryRef)destinationPixBufferAttrs, &callbackRecord, &_decodeSession);
    if (status != noErr) {
        NSLog(@"Create decompression failed");
        return NO;
    }
    //设置解码会话属性(实时编码)
    status = VTSessionSetProperty(_decodeSession, kVTDecompressionPropertyKey_RealTime,kCFBooleanTrue);
    NSLog(@"Set Decode RealTime status:%d", (int)status);
    return YES;
}

- (CVPixelBufferRef)decode: (uint8_t *)frame withSize: (uint32_t)frameSize
{
    CVPixelBufferRef pixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    CMBlockBufferFlags flags = 0;
    
    OSStatus status =  CMBlockBufferCreateWithMemoryBlock(NULL, frame, frameSize, kCFAllocatorNull, NULL, 0, frameSize, flags, &blockBuffer);
    if (status != noErr) {
        NSLog(@"create BlockBuffer failed");
        return NULL;
    }
    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSizeArray[] = {frameSize};
    status = CMSampleBufferCreateReady(NULL, blockBuffer, _decodeDesc, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
    if (status != noErr || !sampleBuffer) {
        NSLog(@"creaet samplebuffer failed");
        CFRelease(blockBuffer);
        return NULL;
    }
    //解码
    //向视频解码器提示使用低功耗模式是可以的
    VTDecodeFrameFlags flag1 = kVTDecodeFrame_1xRealTimePlayback;
    //异步解码
    VTDecodeInfoFlags  infoFlag = kVTDecodeInfo_Asynchronous;
    VTDecompressionSessionDecodeFrame(_decodeSession, sampleBuffer, flag1, &pixelBuffer, &infoFlag);
    if (status == kVTInvalidSessionErr) {
        NSLog(@"Video hard decode  InvalidSessionErr status =%d", (int)status);
    } else if (status == kVTVideoDecoderBadDataErr) {
        NSLog(@"Video hard decode  BadData status =%d", (int)status);
    } else if (status != noErr) {
        NSLog(@"Video hard decode failed status =%d", (int)status);
    }
    CFRelease(sampleBuffer);
    CFRelease(blockBuffer);
    return pixelBuffer;
}

void decompressionCallback(
                                              void * CM_NULLABLE decompressionOutputRefCon,
                                              void * CM_NULLABLE sourceFrameRefCon,
                                              OSStatus status,
                                              VTDecodeInfoFlags infoFlags,
                                              CM_NULLABLE CVImageBufferRef imageBuffer,
                                              CMTime presentationTimeStamp,
                                              CMTime presentationDuration )
{
    if (status != noErr) {
        NSLog(@"decompression callback failed status:%d", (int)status);
        return;
    }
    //解码后的数据sourceFrameRefCon -> CVPixelBufferRef
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
    
    //获取self
    MPVideoDecoder *decoder = (__bridge MPVideoDecoder *)(decompressionOutputRefCon);
    
    //调用回调队列
    dispatch_async(decoder.callbackQueue, ^{
        
        //将解码后的数据给decoder代理.viewController
        [decoder.delegate videoDecoderCallback:imageBuffer];
        //释放数据
        CVPixelBufferRelease(imageBuffer);
    });
}

//销毁
- (void)dealloc
{
    if (_decodeSession) {
        VTDecompressionSessionInvalidate(_decodeSession);
        CFRelease(_decodeSession);
        _decodeSession = NULL;
    }
    
}

@end

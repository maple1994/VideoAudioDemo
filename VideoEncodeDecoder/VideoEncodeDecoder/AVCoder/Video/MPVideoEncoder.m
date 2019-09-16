//
//  AVVideoEncoder.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPVideoEncoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface MPVideoEncoder ()

/// 编码队列
@property (nonatomic, strong) dispatch_queue_t encodeQueue;
/// 回调队列
@property (nonatomic, strong) dispatch_queue_t callbackQueue;
/// 编码session
@property (nonatomic, assign) VTCompressionSessionRef encodeSession;

@end

@implementation MPVideoEncoder
{
    /// 是否已经获取到了pps和sps
    BOOL hasPpsSps;
    long frameID;
}

- (instancetype)initWithConfig: (MPVideoConfig *)config
{
    self = [self init];
    _config = config;
    _encodeQueue = dispatch_queue_create("encoder.queue", DISPATCH_QUEUE_SERIAL);
    _callbackQueue = dispatch_queue_create("callback.queue", DISPATCH_QUEUE_SERIAL);
    // 创建会话
    OSStatus status =  VTCompressionSessionCreate(NULL, (int32_t)_config.width, (int32_t)_config.height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompression, (__bridge void *)self, &_encodeSession);
    if (status != noErr) {
        NSLog(@"Create VTCompressionSession Failed");
        return self;
    }
    // 设置编码属性
    status = VTSessionSetProperty(_encodeSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    NSLog(@"Set RealTime: %d", (int)status);
    // 丢弃B帧
    status = VTSessionSetProperty(_encodeSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    NSLog(@"Set ProfileLevel: %d", (int)status);
    CFNumberRef bit = (__bridge CFNumberRef)@(_config.bitrate);
    // 码率均值
    status = VTSessionSetProperty(_encodeSession, kVTCompressionPropertyKey_AverageBitRate, bit);
    NSLog(@"Set AverageBitRate: %d", (int)status);
    // 码率上限
    CFArrayRef limits = (__bridge CFArrayRef)@[@(_config.bitrate / 4), @(_config.bitrate * 4)];
    status = VTSessionSetProperty(_encodeSession, kVTCompressionPropertyKey_DataRateLimits, limits);
    NSLog(@"Set DataRateLimits: %d", (int)status);
    // 设置GOP间隔
    CFNumberRef gop = (__bridge CFNumberRef)@(_config.fps * 2);
    status = VTSessionSetProperty(_encodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, gop);
    NSLog(@"Set MaxKeyFrameInterval: %d", (int)status);
    // 设置预期fps
    CFNumberRef expectedFps = (__bridge CFNumberRef)@(_config.fps);
    status = VTSessionSetProperty(_encodeSession, kVTCompressionPropertyKey_ExpectedFrameRate, expectedFps);
    NSLog(@"Set ExpectedFrameRate: %d", (int)status);
    // 准备编码
    status = VTCompressionSessionPrepareToEncodeFrames(_encodeSession);
    NSLog(@"Set PrepareToEncodeFrames: %d", (int)status);
    return self;
}

/// 传入sampleBuffer进行编码，通过delegate回调结果
- (void)encodeVideoSampleBuffer: (CMSampleBufferRef)sampleBuffer
{
    CFRetain(sampleBuffer);
    dispatch_async(_encodeQueue, ^{
//        CFRetain(sampleBuffer);
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        self->frameID++;
        CMTime timestamp = CMTimeMake(self->frameID, 1000);
        VTEncodeInfoFlags flags;
        OSStatus status =  VTCompressionSessionEncodeFrame(self.encodeSession, imageBuffer, timestamp, kCMTimeInvalid, NULL, NULL, &flags);
        if (status != noErr) {
            NSLog(@"VTCompressionEncodeFrame failed status: %d", (int)status);
        }
        CFRelease(sampleBuffer);
    });
}

const Byte startCode[] = "\x00\x00\x00\x01";
void didCompression(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
    if (status != noErr) {
        NSLog(@"didCompression encoder error, status: %d", (int)status);
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"CMSampleBufferDataIsReady Failed");
        return;
    }
    MPVideoEncoder *encoder = (__bridge MPVideoEncoder *)outputCallbackRefCon;
    bool keyFrame = !CFDictionaryContainsKey(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), kCMSampleAttachmentKey_NotSync);
    if (keyFrame && !encoder->hasPpsSps)
    {
        size_t spsSize, spsCount;
        size_t ppsSize, ppsCount;
        const uint8_t *spsData, *ppsData;
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        // 获取sps, pps的count和size
        OSStatus status1 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 0, &spsData, &spsSize, &spsCount, 0);
        OSStatus status2 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 1, &ppsData, &ppsSize, &ppsCount, 0);
        if (status1 == noErr && status2 == noErr) {
            encoder->hasPpsSps = YES;
            NSMutableData *sps = [NSMutableData dataWithCapacity:4 + spsSize];
            [sps appendBytes:startCode length:4];
            [sps appendBytes:spsData length: spsSize];
            
            NSMutableData *pps = [NSMutableData dataWithCapacity:4 + ppsSize];
            [pps appendBytes:startCode length:4];
            [pps appendBytes:ppsData length: ppsSize];
            
            dispatch_async(encoder.callbackQueue, ^{
                // 传给代理处理
                [encoder.delegate videoEncoderCallbackSps:sps pps:pps];
            });
        }
    }
    // 获取NALU数据
    size_t lengthAtOffset, totalLength;
    char *dataPointer;
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    OSStatus error = CMBlockBufferGetDataPointer(blockBuffer, 0, &lengthAtOffset, &totalLength, &dataPointer);
    if (error != kCMBlockBufferNoErr) {
        NSLog(@"CMBlockBufferGetDataPointer failed");
        return;
    }
    // 循环获取NALU数据
    size_t offset = 0;
    // 大端长度length
    const int lengthInfoSize = 4;
    while(offset < totalLength - lengthInfoSize)
    {
        uint32_t naluLength = 0;
        // 获取长度
        memcpy(&naluLength, dataPointer + offset, lengthInfoSize);
        // 转系统端
        naluLength = CFSwapInt32BigToHost(naluLength);
        // 获取编码好的数据
        NSMutableData *data = [NSMutableData dataWithCapacity:4 + naluLength];
        [data appendBytes:startCode length:4];
        [data appendBytes:dataPointer + offset + lengthInfoSize length:naluLength];
        // 交给代理处理
        dispatch_async(encoder.callbackQueue, ^{
            [encoder.delegate videoEncoderCallback:data];
        });
        offset += naluLength + lengthInfoSize;
    }
}

- (void)dealloc
{
    if (_encodeSession) {
        VTCompressionSessionCompleteFrames(_encodeSession, kCMTimeInvalid);
        VTCompressionSessionInvalidate(_encodeSession);
        
        CFRelease(_encodeSession);
        _encodeSession = NULL;
    }
    
}

@end

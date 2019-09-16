//
//  ViewController.m
//  VideoToolBoxDemo
//
//  Created by Maple on 2019/8/29.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface ViewController ()<AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureDeviceInput *inputDevice;
@property (nonatomic, strong) AVCaptureVideoDataOutput *outputDevice;
/// 文件操作句柄
@property (nonatomic, strong) NSFileHandle *fileHandle;

@end

@implementation ViewController
{
    /// 帧ID
    int frameID;
    /// 编码session
    VTCompressionSessionRef encodeSession;
    /// 编码格式
    CMFormatDescriptionRef format;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *btn = [[UIButton alloc] init];
    [btn setTitle:@"play" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(btnClick:) forControlEvents:UIControlEventTouchUpInside];
    btn.frame = CGRectMake(100, 30, 50, 50);
    [self.view addSubview:btn];
}

- (void)btnClick: (UIButton *)button
{
    if (!self.session || !self.session.isRunning) {
        [button setTitle:@"stop" forState:UIControlStateNormal];
        [self startRecording];
    }else {
        [button setTitle:@"play" forState:UIControlStateNormal];
        [self stopRecording];
    }
}

- (void)startRecording
{
    self.session = [[AVCaptureSession alloc] init];
    // 设置分辨率
    self.session.sessionPreset = AVCaptureSessionPreset640x480;
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.previewLayer.frame = self.view.bounds;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.previewLayer];
    // 创建输入设备
    NSArray *deivces = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *tmp = nil;
    for (AVCaptureDevice *device in deivces) {
        if (device.position == AVCaptureDevicePositionBack) {
            tmp = device;
            break;
        }
    }
    self.inputDevice = [AVCaptureDeviceInput deviceInputWithDevice:tmp error:nil];
    if ([self.session canAddInput:self.inputDevice]) {
        [self.session addInput:self.inputDevice];
    }
    // 创建输出设备
    self.outputDevice = [[AVCaptureVideoDataOutput alloc] init];
    // 设置不丢弃帧
    [self.outputDevice setAlwaysDiscardsLateVideoFrames:NO];
    NSDictionary *setting = @{(id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]};
    // 设置录取压缩方式为YUV420
    [self.outputDevice setVideoSettings:setting];
    // 设置代理
    [self.outputDevice setSampleBufferDelegate:self queue:dispatch_get_global_queue(0, 0)];
    if ([self.session canAddOutput:self.outputDevice]) {
        [self.session addOutput:self.outputDevice];
    }
    AVCaptureConnection *connection = [self.outputDevice connectionWithMediaType:AVMediaTypeVideo];
    //设置连接的方向
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    // 创建沙盒路径
    NSString *filepath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"test.h264"];
    // 先删除旧文件
    [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
    BOOL res = [[NSFileManager defaultManager] createFileAtPath:filepath contents:nil attributes:nil];
    if (!res) {
        NSLog(@"create file failed");
    }else {
        NSLog(@"create file success");
    }
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:filepath];
    [self initVideoToolBox];
    [self.session startRunning];
}

- (void)stopRecording
{
    [self.session stopRunning];
}

/// 初始化VideoToolBox
- (void)initVideoToolBox
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        self->frameID = 0;
        // 这里的宽高要跟sessionPreset设置的一致
        int width = 480, height = 640;
        // 创建编码session
        OSStatus status =  VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self), &self->encodeSession);
        if (status != 0) {
            NSLog(@"create h264 session failed");
            return;
        }
        // 设置实时编码输出
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        // 是否产生B帧，解码不需要B帧
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
        // 设置关键帧间隔，GOP太小的话，图像会模糊
        int frameInterval = 10;
        CFNumberRef frameIntervalRef = CFNumberCreate(NULL, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        // 设置期望帧率，这里不是实际帧率
        int fps = 10;
        CFNumberRef fpsRef = CFNumberCreate(NULL, kCFNumberIntType, &fps);
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        // 设置码率均值，单位是byte
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(NULL, kCFNumberIntType, &bitRate);
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        // 设置码率上限，单位是bps, YUV420计算 w * h * (3/2) * 8
        int limit = width * height * 3 * 4;
        CFNumberRef limitRef = CFNumberCreate(NULL, kCFNumberIntType, &limit);
        VTSessionSetProperty(self->encodeSession, kVTCompressionPropertyKey_DataRateLimits, limitRef);
        // 开始编码
        VTCompressionSessionPrepareToEncodeFrames(self->encodeSession);
    });
}

void didCompressH264(
                                    void * CM_NULLABLE outputCallbackRefCon,
                                    void * CM_NULLABLE sourceFrameRefCon,
                                    OSStatus status,
                                    VTEncodeInfoFlags infoFlags,
                                    CM_NULLABLE CMSampleBufferRef sampleBuffer )
{
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    // 状态错误
    if (status != 0)
        return;
    // 没准备好
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"sampleBuffer is no ready");
        return;
    }
    // 这里拿到ViewController是为了调用 vc的对象方法
    ViewController *encoder = (__bridge ViewController *)outputCallbackRefCon;
    // 判断当前帧是否为关键帧，原理不详，暂时记住
    bool keyFrame = !CFDictionaryContainsKey(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), kCMSampleAttachmentKey_NotSync);
    //判断当前帧是否为关键帧
    //获取sps & pps 数据 只获取1次，保存在h264文件开头的第一帧中
    //sps(sample per second 采样次数/s),是衡量模数转换（ADC）时采样速率的单位
    //pps()
    if (keyFrame) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        // 获取sps
        size_t spsSize, spsCount;
        const uint8_t *sps;
        OSStatus statusCode =  CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsSize, &spsCount, 0);
        if (statusCode == noErr) {
            // 获取pps
            size_t ppsSize, ppsCount;
            const uint8_t *pps;
            OSStatus statusCode2 =  CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &ppsSize, &ppsCount, 0);
            if (statusCode2 == noErr) {
                NSData *spsData = [NSData dataWithBytes:sps length:spsSize];
                NSData *ppsData = [NSData dataWithBytes:pps length:ppsSize];
                [encoder gotSps:spsData pps:ppsData];
            }
        }
    }
    // 获取编码后的dataBuffer
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    // 起始地址
    char *dataPointer;
    OSStatus res = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (res == noErr) {
        size_t bufferOffset = 0;
        // 返回的NALU数据的前四个字节不是001的startcode，而是大端模式的帧长度length
        static const int headerLength = 4;
        while(bufferOffset < totalLength - headerLength) {
            uint32_t NALUnitLength = 0;
            // 获取NALUnit的长度，从前4个字节读取
            memcpy(&NALUnitLength, dataPointer + bufferOffset, headerLength);
            // 大端模式转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            // 获取nalu数据
            NSData *data = [NSData dataWithBytes:(dataPointer + bufferOffset + headerLength) length:NALUnitLength];
            [encoder gotEncodedData:data];
            // 读取下一个nalu，一次回调可能有多个NALU数据
            bufferOffset += headerLength + NALUnitLength;
        }
    }
}

- (void)encode: (CMSampleBufferRef)sampleBuffer
{
    // 拿到每一帧未编码的数据
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 设置帧时间，如果不设置会导致时间轴过长
    CMTime timeStamp = CMTimeMake(frameID++, 1000);
    VTEncodeInfoFlags flags;
    OSStatus status =  VTCompressionSessionEncodeFrame(encodeSession, imageBuffer, timeStamp, kCMTimeInvalid, NULL, NULL, &flags);
    if (status != noErr) {
        NSLog(@"H264: encode failed");
        VTCompressionSessionInvalidate(encodeSession);
        CFRelease(encodeSession);
        encodeSession = NULL;
        return;
    }
}

- (void)gotEncodedData: (NSData *)data
{
    NSLog(@"gotEncodeData %lu", data.length);
    if (self.fileHandle != NULL) {
        const char bytes[] = "\x00\x00\x00\x01";
        size_t length = sizeof(bytes) - 1;
        NSData *headerByte = [NSData dataWithBytes:bytes length:length];
        [_fileHandle writeData:headerByte];
        [_fileHandle writeData:data];
    }
}

// 第一帧写入sps，pps
- (void)gotSps: (NSData *)sps pps: (NSData *)pps
{
    NSLog(@"gotSps: %lu %lu", (unsigned long)sps.length, pps.length);
    // 起始码都是 00 00 00 01
    const char bytes[] = "\x00\x00\x00\x01";
    // 去掉字符最后的\n
    size_t length = sizeof(bytes) - 1;
    NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
    [self.fileHandle writeData:byteHeader];
    [self.fileHandle writeData:sps];
    [self.fileHandle writeData:byteHeader];
    [self.fileHandle writeData:pps];
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    dispatch_sync(dispatch_get_global_queue(0, 0), ^{
        [self encode:sampleBuffer];
    });
}

@end

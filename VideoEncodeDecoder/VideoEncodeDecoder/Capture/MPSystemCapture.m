//
//  MPSystemCapture.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPSystemCapture.h"

@interface MPSystemCapture ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>

/***************** 公共 *******************/
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) dispatch_queue_t captureQueue;
@property (nonatomic, assign) MPSystemCaptureType captureType;
@property (nonatomic, assign) BOOL isRunning;
/***************** 音频 *******************/
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInputDevice;
@property (nonatomic, strong) AVCaptureConnection *audioConnection;
/***************** 视频 *******************/
/// 前置摄像头
@property (nonatomic, strong) AVCaptureDeviceInput *frontCamera;
/// 后置摄像头
@property (nonatomic, strong) AVCaptureDeviceInput *backCamera;
/// 当前的摄像头设备
@property (nonatomic, strong) AVCaptureDeviceInput *videoInputDevice;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureConnection *videoConnection;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preLayer;
@property (nonatomic, assign) CGSize prelayerSize;

@end

@implementation MPSystemCapture

- (void)dealloc
{
    [self destoryCaptureSession];
}

// MARK: - Public
- (instancetype)initWithType: (MPSystemCaptureType)type
{
    self = [super init];
    _captureType = type;
    return self;
}

/// 准备工作，只捕获音频时调用
- (void)prepare
{
    [self prepareWithPreviewSize:CGSizeZero];
}
/// 捕获内容包括视频时调用，size是设置预览层的大小
- (void)prepareWithPreviewSize: (CGSize)size
{
    _prelayerSize = size;
    switch (self.captureType) {
        case MPSystemCaptureTypeAudio:
            [self setupAudio];
            break;
        case MPSystemCaptureTypeVideo:
            [self setupVideo];
            break;
        case MPSystemCaptureTypeAll:
            [self setupAudio];
            [self setupVideo];
            break;
    }
}
/// 开始捕获
- (void)start
{
    if (!self.isRunning) {
        self.isRunning = YES;
        [self.session startRunning];
    }
}

/// 结束
- (void)stop
{
    if (self.isRunning) {
        self.isRunning = NO;
        [self.session stopRunning];
    }
}

/// 切换摄像头
- (void)changeCamera
{
    [self.session beginConfiguration];
    [self.session removeInput:self.videoInputDevice];
    if ([self.videoInputDevice isEqual:self.frontCamera]) {
        self.videoInputDevice = self.backCamera;
    }else {
        self.videoInputDevice = self.frontCamera;
    }
    if ([self.session canAddInput:self.videoInputDevice]) {
        [self.session addInput:self.videoInputDevice];
    }
    [self.session commitConfiguration];
}

// MARK: - Private
- (void)setupAudio
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    self.audioInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioOutput setSampleBufferDelegate:self queue:self.captureQueue];
    [self.session beginConfiguration];
    if ([self.session canAddInput:self.audioInputDevice]) {
        [self.session addInput:self.audioInputDevice];
    }
    if ([self.session canAddOutput:self.audioOutput]) {
        [self.session addOutput:self.audioOutput];
    }
    [self.session commitConfiguration];
    self.audioConnection = [self.audioOutput connectionWithMediaType:AVMediaTypeAudio];
}

- (void)setupVideo
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == AVCaptureDevicePositionFront) {
            self.frontCamera = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
        }else if (device.position == AVCaptureDevicePositionBack) {
            self.backCamera = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];;
        }
    }
    // 默认选择后置摄像头
    self.videoInputDevice = self.backCamera;
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setSampleBufferDelegate:self queue:self.captureQueue];
    [self.videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    // 设置输出格式为YUV420
    NSDictionary *setting = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    [self.videoOutput setVideoSettings:setting];
    [self.session beginConfiguration];
    if ([self.session canAddInput:self.videoInputDevice]) {
        [self.session addInput:self.videoInputDevice];
    }
    if ([self.session canAddOutput:self.videoOutput]) {
        [self.session addOutput:self.videoOutput];
    }
    // 设置分辨率
    [self setupVideoPreset];
    [self.session commitConfiguration];
    // commit后以下代码才生效
    self.videoConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [self updateFps:25];
    [self setupPreviewLayer];
}

/// 设置分辨率
- (void)setupVideoPreset
{
    if ([self.session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        self.session.sessionPreset = AVCaptureSessionPreset1920x1080;
        _width = 1080;
        _height = 1920;
    }else if ([self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        self.session.sessionPreset = AVCaptureSessionPreset1280x720;
        _width = 720;
        _height = 1280;
    }else {
        self.session.sessionPreset = AVCaptureSessionPreset640x480;
        _width = 480;
        _height = 640;
    }
}

/// 设置FPS
- (void)updateFps: (NSUInteger)fps
{
    NSArray *deviceArr = [AVCaptureDevice deviceWithUniqueID:AVMediaTypeVideo];
    for (AVCaptureDevice *device in deviceArr) {
        // 获取当前支持的最大fps
        float maxRate = [(AVFrameRateRange *)[device.activeFormat.videoSupportedFrameRateRanges objectAtIndex:0] maxFrameRate];
        if (maxRate >= fps) {
            if ([device lockForConfiguration:nil]) {
                device.activeVideoMinFrameDuration = CMTimeMake(10, (int)(fps * 10));
                device.activeVideoMaxFrameDuration = device.activeVideoMinFrameDuration;
                [device unlockForConfiguration];
            }
        }
    }
}

/// 设置预览层
- (void)setupPreviewLayer
{
    self.preLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.preLayer.frame = CGRectMake(0, 0, self.prelayerSize.width, self.prelayerSize.height);
    self.preLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.preview.layer addSublayer:self.preLayer];
}

- (void)destoryCaptureSession
{
    if (self.session) {
        switch (self.captureType) {
            case MPSystemCaptureTypeAudio:
                [self.session removeInput:self.audioInputDevice];
                [self.session removeOutput:self.audioOutput];
                break;
            case MPSystemCaptureTypeVideo:
                [self.session removeInput:self.videoInputDevice];
                [self.session removeOutput:self.videoOutput];
                break;
            case MPSystemCaptureTypeAll:
                [self.session removeInput:self.audioInputDevice];
                [self.session removeOutput:self.audioOutput];
                [self.session removeInput:self.videoInputDevice];
                [self.session removeOutput:self.videoOutput];
                break;
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (connection == self.audioConnection) {
        // 音频数据回调
        if ([self.delegate respondsToSelector:@selector(captureSampleBuffer:type:)]) {
            [self.delegate captureSampleBuffer:sampleBuffer type:MPSystemCaptureTypeAudio];
        }
    }else {
        // 视频数据回调
        if ([self.delegate respondsToSelector:@selector(captureSampleBuffer:type:)]) {
            [self.delegate captureSampleBuffer:sampleBuffer type:MPSystemCaptureTypeVideo];
        }
    }
}

// MARK: - Getter
- (AVCaptureSession *)session
{
    if (!_session) {
        _session = [[AVCaptureSession alloc] init];
    }
    return _session;
}

- (dispatch_queue_t)captureQueue
{
    if (!_captureQueue) {
        // NULL代表创建的是串行队列
        _captureQueue = dispatch_queue_create("com.maple", NULL);
    }
    return _captureQueue;
}

- (UIView *)preview
{
    if (!_preview) {
        _preview = [[UIView alloc] init];
    }
    return _preview;
}

@end

//
//  ViewController.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "ViewController.h"
#import "MPSystemCapture.h"
#import "MPVideoEncoder.h"
#import "MPVideoDecoder.h"
#import "MPEAGLLayer.h"
#import "MPAudioEncoder.h"
#import "MPAudioDecoder.h"
#import "CCAudioPCMPlayer.h"

@interface ViewController ()<MPSystemCaptureDelegate, MPVideoEncoderDelegate,
    MPVideoDecoderDelegate,
    MPAudioEncoderDelegate,
    MPAudioDecoderDelegate>

@property (nonatomic, strong) MPSystemCapture *capture;
@property (nonatomic, strong) MPVideoEncoder *videoEncoder;
@property (nonatomic, strong) MPVideoDecoder *videoDecoder;
@property (nonatomic, strong) MPEAGLLayer *displayLayer;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSFileHandle *audioFileHandle;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) MPAudioEncoder *audioEncoder;
@property (nonatomic, strong) MPAudioDecoder *audioDecoder;
@property (nonatomic, strong) CCAudioPCMPlayer *pcmPlayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setup];
}

- (void)setup
{
    _pcmPlayer = [[CCAudioPCMPlayer alloc]initWithConfig:[MPAudioConfig defaultConfig]];
    self.capture = [[MPSystemCapture alloc] initWithType:MPSystemCaptureTypeAll];
    CGSize size = CGSizeMake(self.view.frame.size.width * 0.5, self.view.frame.size.height * 0.5);
    [self.capture prepareWithPreviewSize:size];
    self.capture.delegate = self;
    self.capture.preview.frame = CGRectMake(0, 100, size.width, size.height);
    [self.view addSubview:self.capture.preview];
    
    self.path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"test.h264"];
    NSString *audioPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"audio.aac"];
    _fileHandle = [self fileHandleWithPath:self.path];
    _audioFileHandle = [self fileHandleWithPath:audioPath];
    NSLog(@"%@\n%@", self.path, audioPath);
    
    MPVideoConfig *config = [MPVideoConfig defaultConfig];
    config.width = self.capture.width;
    config.height = self.capture.height;
    config.bitrate = config.width * config.height * 5;
    _videoEncoder = [[MPVideoEncoder alloc] initWithConfig:config];
    _videoEncoder.delegate = self;
    _videoDecoder = [[MPVideoDecoder alloc] initWithConfig:config];
    _videoDecoder.delegate = self;
    
    _displayLayer = [[MPEAGLLayer alloc] initWithFrame:CGRectMake(size.width, 100, size.width, size.height)];
    [self.view.layer addSublayer:_displayLayer];
    
    _audioEncoder = [[MPAudioEncoder alloc] initWithConfig:[MPAudioConfig defaultConfig]];
    _audioEncoder.delegate = self;
    _audioDecoder = [[MPAudioDecoder alloc] initWithConfig:[MPAudioConfig defaultConfig]];
    _audioDecoder.delegate = self;
}

- (NSFileHandle *)fileHandleWithPath: (NSString *)path
{
    NSFileManager *mgr = [NSFileManager defaultManager];
    if ([mgr fileExistsAtPath:path]) {
        [mgr removeItemAtPath:path error:nil];
    }
    [mgr createFileAtPath:path contents:nil attributes:nil];
    return [NSFileHandle fileHandleForWritingAtPath:path];
}

- (IBAction)startCapture {
    [self.capture start];
}

- (IBAction)stopCapture {
    [self.capture stop];
    [_fileHandle closeFile];
    [_audioFileHandle closeFile];
}

- (IBAction)closeFile {
    [_fileHandle closeFile];
    [_audioFileHandle closeFile];
}

// MARK: - MPSystemCaptureDelegate
- (void)captureSampleBuffer:(CMSampleBufferRef)sampleBuffer type:(MPSystemCaptureType)type
{
    if (type == MPSystemCaptureTypeVideo) {
        [self.videoEncoder encodeVideoSampleBuffer:sampleBuffer];
    }else if (type == MPSystemCaptureTypeAudio){
        [self.audioEncoder encodeAudioSampleBuffer:sampleBuffer];
    }
}

// MARK: - MPVideoEncoderDelegate
- (void)videoEncoderCallback:(NSData *)h264Data
{
//    [self.videoDecoder decodeNaluData:h264Data];
    [self.fileHandle seekToEndOfFile];
    [self.fileHandle writeData:h264Data];
}

- (void)videoEncoderCallbackSps:(NSData *)sps pps:(NSData *)pps
{
//    [self.videoDecoder decodeNaluData:sps];
//    [self.videoDecoder decodeNaluData:pps];
    [self.fileHandle seekToEndOfFile];
    [self.fileHandle writeData:sps];
    [self.fileHandle seekToEndOfFile];
    [self.fileHandle writeData:pps];
}

// MARK: - MPVideoDecoderDelegate
- (void)videoDecoderCallback:(CVPixelBufferRef)imageBuffer
{
    if (imageBuffer) {
        self.displayLayer.pixelBuffer = imageBuffer;
    }
}

// MARK: - MPAudioEncoderDelegate & MPAudioDecoderDelegate
- (void)audioEncoderCallback:(NSData *)aacData
{
//    [self.audioFileHandle seekToEndOfFile];
//    [self.audioFileHandle writeData:aacData];
    [self.audioDecoder decodeAudioAACData:aacData];
}

- (void)audioDecodeCallback:(NSData *)pcmData
{
    [_pcmPlayer playPCMData:pcmData];
}

@end

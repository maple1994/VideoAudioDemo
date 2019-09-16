
#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "NSFileManager+THAdditions.h"

NSString *const THThumbnailCreatedNotification = @"THThumbnailCreated";

@interface THCameraController () <AVCaptureFileOutputRecordingDelegate>

@property (strong, nonatomic) dispatch_queue_t videoQueue; //视频队列
@property (strong, nonatomic) AVCaptureSession *captureSession;// 捕捉会话
@property (weak, nonatomic) AVCaptureDeviceInput *activeVideoInput;//输入
@property (strong, nonatomic) AVCaptureStillImageOutput *imageOutput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieOutput;
@property (strong, nonatomic) NSURL *outputURL;

@end

@implementation THCameraController

- (BOOL)setupSession:(NSError **)error {
    self.captureSession = [[AVCaptureSession alloc] init];
    // 设置分辨率
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    // 获取默认摄像头
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error];
    if (videoInput && [self.captureSession canAddInput:videoInput]) {
        [self.captureSession addInput:videoInput];
        self.activeVideoInput = videoInput;
    }else {
        return NO;
    }
    // 添加录音设备
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:error];
    if (audioInput && [self.captureSession canAddInput:audioInput]) {
        [self.captureSession addInput:audioInput];
    }else {
        return NO;
    }
    /*---- 创建输出设备 ----*/
    // 从摄像头铺抓静态图片
    self.imageOutput = [[AVCaptureStillImageOutput alloc] init];
    // 设置文件格式
    self.imageOutput.outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG};
    if ([self.captureSession canAddOutput:self.imageOutput]) {
        [self.captureSession addOutput:self.imageOutput];
    }
    self.movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([self.captureSession canAddOutput:self.movieOutput]) {
        [self.captureSession addOutput:self.movieOutput];
    }
    // 创建线程队列
    self.videoQueue = dispatch_queue_create("mp.videoQueue", DISPATCH_QUEUE_CONCURRENT);
    return YES;
}

- (void)startSession {
    if (!self.captureSession.isRunning) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {
    if (self.captureSession.isRunning) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }
}

//- (dispatch_queue_t)globalQueue {
//    
//    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//}

#pragma mark - Device Configuration   配置摄像头支持的方法
/// 返回指定方向的设备
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for(AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

/// 获取激活的摄像头
- (AVCaptureDevice *)activeCamera {
    return self.activeVideoInput.device;
}

//返回当前未激活的摄像头
- (AVCaptureDevice *)inactiveCamera {
    AVCaptureDevice *device = nil;
    if (self.cameraCount > 1) {
        if ([self activeCamera].position == AVCaptureDevicePositionBack) {
            device = [self cameraWithPosition:AVCaptureDevicePositionFront];
        }else {
            device = [self cameraWithPosition:AVCaptureDevicePositionBack];
        }
    }
    return device;
}

//判断是否有超过1个摄像头可用
- (BOOL)canSwitchCameras {
    return self.cameraCount > 1;
}

//可用视频捕捉设备的数量
- (NSUInteger)cameraCount {
    return [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count;
}

//切换摄像头
- (BOOL)switchCameras {
    if (![self canSwitchCameras]) {
        return NO;
    }
    NSError *error;
    AVCaptureDevice *device = [self inactiveCamera];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (videoInput) {
        // 开始修改session配置
        [self.captureSession beginConfiguration];
        [self.captureSession removeInput:self.activeVideoInput];
        if ([self.captureSession canAddInput:videoInput]) {
            [self.captureSession addInput: videoInput];
            self.activeVideoInput = videoInput;
        }else {
            // 无法加入时，继续沿用原来的摄像头
            [self.captureSession addInput: self.activeVideoInput];
        }
        [self.captureSession commitConfiguration];
    }else {
        [self.delegate deviceConfigurationFailedWithError:error];
    }
    return NO;
}

/*
    AVCapture Device 定义了很多方法，让开发者控制ios设备上的摄像头。可以独立调整和锁定摄像头的焦距、曝光、白平衡。对焦和曝光可以基于特定的兴趣点进行设置，使其在应用中实现点击对焦、点击曝光的功能。
    还可以让你控制设备的LED作为拍照的闪光灯或手电筒的使用
    
    每当修改摄像头设备时，一定要先测试修改动作是否能被设备支持。并不是所有的摄像头都支持所有功能，例如牵制摄像头就不支持对焦操作，因为它和目标距离一般在一臂之长的距离。但大部分后置摄像头是可以支持全尺寸对焦。尝试应用一个不被支持的动作，会导致异常崩溃。所以修改摄像头设备前，需要判断是否支持
 
 
 */


#pragma mark - Focus Methods 点击聚焦方法的实现

- (BOOL)cameraSupportsTapToFocus {
    return [self activeCamera].isFocusPointOfInterestSupported;
}

- (void)focusAtPoint:(CGPoint)point {
    AVCaptureDevice *device = [self activeCamera];
    // 是否支持兴趣点对焦 & 自动对焦
    if ([self cameraSupportsTapToFocus] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        // 加锁，修改
        if ([device lockForConfiguration:&error]) {
            device.focusPointOfInterest = point;
            device.focusMode = AVCaptureFocusModeAutoFocus;
            [device unlockForConfiguration];
        }else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}

#pragma mark - Exposure Methods   点击曝光的方法实现

- (BOOL)cameraSupportsTapToExpose {
    return [self activeCamera].isExposurePointOfInterestSupported;
}

static const NSString *THCameraAdjustingExposureContext;

- (void)exposeAtPoint:(CGPoint)point {
    AVCaptureDevice *device = [self activeCamera];
    AVCaptureExposureMode mode = AVCaptureExposureModeAutoExpose;
    NSError *error;
    if (device.isExposurePointOfInterestSupported &&
        [device isExposureModeSupported:mode]) {
        if ([device lockForConfiguration:&error]) {
            device.exposurePointOfInterest = point;
            device.exposureMode = mode;
            // 判断设备是否支持锁定曝光模式
            if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
                [device addObserver:self forKeyPath:@"adjustingExposure" options:NSKeyValueObservingOptionNew context:&THCameraAdjustingExposureContext];
            }
            [device unlockForConfiguration];
        }else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &THCameraAdjustingExposureContext) {
        AVCaptureDevice *device = (AVCaptureDevice *)object;
        // 判断设备是否不再调整曝光等级
        if (!device.isAdjustingExposure && [device isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [object removeObserver:self forKeyPath:@"adjustingExposure" context:&THCameraAdjustingExposureContext];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error;
                if ([device lockForConfiguration:&error]) {
                    device.exposureMode = AVCaptureExposureModeLocked;
                    [device unlockForConfiguration];
                }else {
                    [self.delegate deviceConfigurationFailedWithError:error];
                }
            });
        }
    }else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

//重新设置对焦&曝光
- (void)resetFocusAndExposureModes {
    AVCaptureDevice *device = [self activeCamera];
    AVCaptureFocusMode focusMode = AVCaptureFocusModeContinuousAutoFocus;
    // 是否可以重设对焦
    BOOL canResetFocus = device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode];
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeAutoExpose;
    // 是否可以重设曝光
    BOOL canResetExposure = device.isExposurePointOfInterestSupported&& [device isExposureModeSupported:exposureMode];
    CGPoint center = CGPointMake(0.5, 0.5);
    NSError *error;
    if ([device lockForConfiguration:&error]) {
        if (canResetFocus) {
            device.focusPointOfInterest = center;
            device.focusMode = focusMode;
        }
        if (canResetExposure) {
            device.exposurePointOfInterest = center;
            device.exposureMode = exposureMode;
        }
        [device unlockForConfiguration];
    }else {
        [self.delegate deviceConfigurationFailedWithError:error];
    }
}



#pragma mark - Flash and Torch Modes    闪光灯 & 手电筒

//判断是否有闪光灯
- (BOOL)cameraHasFlash {
    return [self activeCamera].hasFlash;
}

//闪光灯模式
- (AVCaptureFlashMode)flashMode {
    return [self activeCamera].flashMode;
}

//设置闪光灯
- (void)setFlashMode:(AVCaptureFlashMode)flashMode {
    AVCaptureDevice *device = [self activeCamera];
    if ([device isFlashModeSupported:flashMode]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        }else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
    
}

//是否支持手电筒
- (BOOL)cameraHasTorch {
    return [self activeCamera].hasTorch;
}

//手电筒模式
- (AVCaptureTorchMode)torchMode {
    return [self activeCamera].torchMode;
}


//设置是否打开手电筒
- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    AVCaptureDevice *device = [self activeCamera];
    if ([device isTorchModeSupported:torchMode]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        }else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}


#pragma mark - Image Capture Methods 拍摄静态图片
/*
    AVCaptureStillImageOutput 是AVCaptureOutput的子类。用于捕捉图片
 */
- (void)captureStillImage {
    // 获取连接
    AVCaptureConnection *connection = [self.imageOutput connectionWithMediaType:AVMediaTypeVideo];
    // 获取方向支持
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = [self currentVideoOrientation];
    }
    // 获取静态图片
    [self.imageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef  _Nullable imageDataSampleBuffer, NSError * _Nullable error) {
        if (imageDataSampleBuffer != NULL) {
            NSData *data = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
            UIImage *image = [UIImage imageWithData:data];
            [self writeImageToAssetsLibrary:image];
        }else {
            NSLog(@"NULL imageDataSampleBuffer, %@", error.localizedDescription);
        }
    }];
}

//获取方向值
- (AVCaptureVideoOrientation)currentVideoOrientation {
    AVCaptureVideoOrientation orientation;
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationLandscapeLeft:
            orientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
            
    }
    return orientation;
}


/*
    Assets Library 框架 
    用来让开发者通过代码方式访问iOS photo
    注意：会访问到相册，需要修改plist 权限。否则会导致项目崩溃
 */

- (void)writeImageToAssetsLibrary:(UIImage *)image {
    ALAssetsLibrary *lib = [[ALAssetsLibrary alloc] init];
    [lib writeImageToSavedPhotosAlbum:image.CGImage orientation:(NSUInteger)image.imageOrientation completionBlock:^(NSURL *assetURL, NSError *error) {
        if (!error) {
            [self postThumbnailNotifification:image];
        }else {
            NSLog(@"%@", error.localizedDescription);
        }
    }];
}

//发送缩略图通知
- (void)postThumbnailNotifification:(UIImage *)image {
    [[NSNotificationCenter defaultCenter] postNotificationName:THThumbnailCreatedNotification object:image];
}

#pragma mark - Video Capture Methods 捕捉视频

//判断是否录制状态
- (BOOL)isRecording {
    return self.movieOutput.isRecording;
}

//开始录制
- (void)startRecording {
    if (![self isRecording]) {
        AVCaptureConnection *connection = [self.movieOutput connectionWithMediaType:AVMediaTypeVideo];
        if ([connection isVideoOrientationSupported]) {
            connection.videoOrientation = [self currentVideoOrientation];
        }
        // 是否支持视频稳定
        if ([connection isVideoStabilizationSupported]) {
            connection.enablesVideoStabilizationWhenAvailable = YES;
        }
        AVCaptureDevice *device = [self activeCamera];
        if (device.isSmoothAutoFocusSupported) {
            NSError *error;
            if ([device lockForConfiguration:&error]) {
                device.smoothAutoFocusEnabled = YES;
                [device unlockForConfiguration];
            }else {
                [self.delegate mediaCaptureFailedWithError:error];
            }
        }
        self.outputURL = [self uniqueURL];
        // 开始录制
        [self.movieOutput startRecordingToOutputFileURL:self.outputURL recordingDelegate:self];
    }
}

- (CMTime)recordedDuration {
    return self.movieOutput.recordedDuration;
}


//写入视频唯一文件系统URL
- (NSURL *)uniqueURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    //temporaryDirectoryWithTemplateString  可以将文件写入的目的创建一个唯一命名的目录；
    NSString *dirPath = [fileManager temporaryDirectoryWithTemplateString:@"kamera.XXXXXX"];
    if (dirPath) {
        NSString *filePath = [dirPath stringByAppendingPathComponent:@"kamera_movie.mov"];
        return  [NSURL fileURLWithPath:filePath];
    }
    return nil;
}

//停止录制
- (void)stopRecording {
    if (self.movieOutput.isRecording) {
        [self.movieOutput stopRecording];
    }
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error {
    if (error) {
        [self.delegate mediaCaptureFailedWithError:error];
    }else {
        [self writeVideoToAssetsLibrary:self.outputURL];
    }
    self.outputURL = nil;
}

//写入捕捉到的视频
- (void)writeVideoToAssetsLibrary:(NSURL *)videoURL {
    ALAssetsLibrary *lib = [[ALAssetsLibrary alloc] init];
    // 先判断，后写入
    if ([lib videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL]) {
        [lib writeVideoAtPathToSavedPhotosAlbum:videoURL completionBlock:^(NSURL *assetURL, NSError *error) {
            if (error) {
                [self.delegate assetLibraryWriteFailedWithError:error];
            }else {
                [self generateThumbnailForVideoAtURL:videoURL];
            }
        }];
    }
}

//获取视频左下角缩略图
- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {
    dispatch_async(self.videoQueue, ^{
        AVAsset *asset = [AVAsset assetWithURL:videoURL];
        AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        // 根据宽算高
        imageGenerator.maximumSize = CGSizeMake(100, 0);
        // 会应用视频变换
        imageGenerator.appliesPreferredTrackTransform = YES;
        CGImageRef imageRef = [imageGenerator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postThumbnailNotifification:image];
        });
    });
}


@end



#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>

@interface THCameraController ()<AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;

@end

@implementation THCameraController

- (BOOL)setupSessionOutputs:(NSError **)error {
    self.metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if ([self.captureSession canAddOutput:self.metadataOutput]) {
        [self.captureSession addOutput:self.metadataOutput];
        // 指定检测的类型
        self.metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeFace];
        // 人脸检测要放在主线程操作
        [self.metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    }
    return NO;
}



//捕捉数据
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataFaceObject *face in metadataObjects) {
        NSLog(@"faceID: %ld, face bounds: %@", (long)face.faceID, NSStringFromCGRect(face.bounds));
    }
    [self.faceDetectionDelegate didDetectFaces:metadataObjects];
}

@end


//
//  MPSystemCapture.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, MPSystemCaptureType) {
    MPSystemCaptureTypeVideo = 0,
    MPSystemCaptureTypeAudio,
    MPSystemCaptureTypeAll
};

@protocol MPSystemCaptureDelegate <NSObject>

- (void)captureSampleBuffer: (CMSampleBufferRef)sampleBuffer type: (MPSystemCaptureType)type;

@end

@interface MPSystemCapture : NSObject

/// 预览层
@property (nonatomic, strong) UIView *preview;
@property (nonatomic, weak) id<MPSystemCaptureDelegate> delegate;
/// 视频宽
@property (nonatomic, assign, readonly) NSUInteger width;
/// 视频高
@property (nonatomic, assign, readonly) NSUInteger height;

- (instancetype)initWithType: (MPSystemCaptureType)type;
- (instancetype)init UNAVAILABLE_ATTRIBUTE;

/// 准备工作，只捕获音频时调用
- (void)prepare;
/// 捕获内容包括视频时调用，size是设置预览层的大小
- (void)prepareWithPreviewSize: (CGSize)size;
/// 开始捕获
- (void)start;
/// 结束
- (void)stop;
/// 切换摄像头
- (void)changeCamera;

@end

NS_ASSUME_NONNULL_END

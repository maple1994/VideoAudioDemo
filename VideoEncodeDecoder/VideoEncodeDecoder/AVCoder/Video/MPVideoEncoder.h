//
//  AVVideoEncoder.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "MPAVConfig.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MPVideoEncoderDelegate <NSObject>

/// h264数据编码完成回调
- (void)videoEncoderCallback: (NSData *)h264Data;
/// sps & pps 数据编码回调
- (void)videoEncoderCallbackSps: (NSData *)sps pps: (NSData *)pps;

@end


@interface MPVideoEncoder : NSObject

@property (nonatomic, strong) MPVideoConfig *config;
@property (nonatomic, weak) id<MPVideoEncoderDelegate> delegate;

- (instancetype)initWithConfig: (MPVideoConfig *)config;

/// 传入sampleBuffer进行编码，通过delegate回调结果
- (void)encodeVideoSampleBuffer: (CMSampleBufferRef)sampleBuffer;

@end

NS_ASSUME_NONNULL_END

//
//  AVVideoDecoder.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "MPAVConfig.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MPVideoDecoderDelegate <NSObject>

/// 解码后h264数据回调
- (void)videoDecoderCallback: (CVPixelBufferRef)imageBuffer;

@end

@interface MPVideoDecoder : NSObject

@property (nonatomic, weak) id<MPVideoDecoderDelegate> delegate;
@property (nonatomic, strong) MPVideoConfig *config;

- (instancetype)initWithConfig: (MPVideoConfig *)config;

/// 开始编码
- (void)decodeNaluData: (NSData *)data;

@end

NS_ASSUME_NONNULL_END

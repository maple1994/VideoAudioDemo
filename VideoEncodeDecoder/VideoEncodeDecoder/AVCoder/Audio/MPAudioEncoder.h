//
//  MPAudioEncoder.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/11.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
@class MPAudioConfig;
NS_ASSUME_NONNULL_BEGIN

@protocol MPAudioEncoderDelegate <NSObject>

- (void)audioEncoderCallback: (NSData *)aacData;

@end

@interface MPAudioEncoder : NSObject

@property (nonatomic, strong) MPAudioConfig *config;
@property (nonatomic, weak) id<MPAudioEncoderDelegate> delegate;

- (instancetype)initWithConfig: (MPAudioConfig *)config;
/// 编码
- (void)encodeAudioSampleBuffer: (CMSampleBufferRef)sampleBuffer;

@end

NS_ASSUME_NONNULL_END

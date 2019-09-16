//
//  MPAudioDecoder.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/11.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
@class MPAudioConfig;
NS_ASSUME_NONNULL_BEGIN

@protocol MPAudioDecoderDelegate <NSObject>

- (void)audioDecodeCallback:(NSData *)pcmData;

@end

@interface MPAudioDecoder : NSObject

@property (nonatomic, strong) MPAudioConfig *config;
@property (nonatomic, weak) id<MPAudioDecoderDelegate> delegate;

- (instancetype)initWithConfig: (MPAudioConfig *)config;
- (void)decodeAudioAACData: (NSData *)data;

@end

NS_ASSUME_NONNULL_END

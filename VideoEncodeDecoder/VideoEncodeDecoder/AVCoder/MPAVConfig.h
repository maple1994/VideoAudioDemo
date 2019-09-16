//
//  MPAVConfig.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAudioConfig : NSObject

/// 码率，96000
@property (nonatomic, assign) NSInteger bitrate;
/// 声道，1
@property (nonatomic, assign) NSInteger channelCount;
/// 采样率 44100
@property (nonatomic, assign) NSInteger sampleRate;
/// 采样点量化，16
@property (nonatomic, assign) NSInteger sampleSize;

+ (instancetype)defaultConfig;

@end

@interface MPVideoConfig: NSObject

@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) NSInteger bitrate;
@property (nonatomic, assign) NSInteger fps;

+ (instancetype)defaultConfig;

@end

NS_ASSUME_NONNULL_END

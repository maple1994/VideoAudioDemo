//
//  MPAVConfig.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/2.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPAVConfig.h"

@implementation MPAudioConfig

+ (instancetype)defaultConfig
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if (self = [super init]) {
        self.bitrate = 96000;
        self.channelCount = 1;
        self.sampleSize = 16;
        self.sampleRate = 44100;
    }
    return self;
}


@end

@implementation MPVideoConfig;

+ (instancetype)defaultConfig
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if (self = [super init]) {
        self.width = 480;
        self.height = 640;
        self.bitrate = 640 * 1000;
        self.fps = 25;
    }
    return self;
}

@end

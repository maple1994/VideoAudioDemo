//
//  MPEAGLLayer.h
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/6.
//  Copyright © 2019 Maple. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPEAGLLayer : CAEAGLLayer

@property (nonatomic, assign) CVPixelBufferRef pixelBuffer;

- (instancetype)initWithFrame: (CGRect)frame;
- (void)resetRenderBuffer;

@end

NS_ASSUME_NONNULL_END

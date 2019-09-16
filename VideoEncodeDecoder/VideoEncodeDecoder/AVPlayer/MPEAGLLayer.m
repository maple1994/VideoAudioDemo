//
//  MPEAGLLayer.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/6.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPEAGLLayer.h"
#import <AVFoundation/AVFoundation.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/EAGL.h>
#import <mach/mach_time.h>

// Unifrom Index
enum
{
    UNIFROM_Y,
    UNIFORM_UV,
    UNIFORM_ROTATION_ANGLE,
    UNIFORM_COLOR_COVERSEION_MATRIX,
    UNIFORM_NUM
};
GLint uniforms[UNIFORM_NUM];

// Arribute index
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    ATTRIB_NUM
};

//YUV->RGB
//颜色转换常量（yuv到rgb），包括从16-235/16-240（视频范围）进行调整
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, 这是高清电视的标准
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

@interface MPEAGLLayer()
{
    GLint _backingWidth;
    GLint _backingHeight;
    EAGLContext *_context;
    // YUV分为亮度和色度两个纹理
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    // 帧缓冲区
    GLuint _frameBufferHandle;
    // 颜色缓冲区
    GLuint _colorBufferHandle;
    // 选择颜色通道
    const GLfloat *_preferredConversion;
}

@property (nonatomic, assign) GLuint program;

@end

@implementation MPEAGLLayer

- (instancetype)initWithFrame: (CGRect)frame
{
    self = [super init];
    CGFloat scale = [UIScreen mainScreen].scale;
    self.contentsScale = scale;
    // 设置完全不透明
    self.opaque = YES;
    // 绘制表面再显示后，是否保留刘内，设置为YES
    self.drawableProperties = @{
                                kEAGLDrawablePropertyRetainedBacking: [NSNumber numberWithBool:YES]
                                };
    [self setFrame:frame];
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:_context];
    // YUV转换矩阵使用BT.709
    _preferredConversion = kColorConversion709;
    [self setupGL];
    return self;
}

- (void)resetRenderBuffer
{
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        return;
    }
    
    [self releaseBuffers];
    [self createBuffers];
}

//释放帧缓存区与渲染缓存区
- (void) releaseBuffers
{
    if(_frameBufferHandle) {
        glDeleteFramebuffers(1, &_frameBufferHandle);
        _frameBufferHandle = 0;
    }
    
    if(_colorBufferHandle) {
        glDeleteRenderbuffers(1, &_colorBufferHandle);
        _colorBufferHandle = 0;
    }
}

- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    _pixelBuffer = CVPixelBufferRetain(pixelBuffer);
    // 获取宽高
    int frameWidth = (int)CVPixelBufferGetWidth(_pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(_pixelBuffer);
    // 显示_pixelBuffer
    [self displayPixelBuffer:pixelBuffer width:frameWidth height:frameHeight];
}

- (void)displayPixelBuffer: (CVPixelBufferRef)pixelBuffer width: (int)width height: (int)height
{
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        return;
    }
    if (pixelBuffer == NULL) {
        NSLog(@"pixelBuffer is NULL");
        return;
    }
    CVReturn err;
    // 获取像素缓冲区的平面数
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    // 使用像素缓冲区的颜色附件确定适当的颜色转化矩阵
    CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
        _preferredConversion = kColorConversion601;
    }else {
        _preferredConversion = kColorConversion709;
    }
    CVOpenGLESTextureCacheRef _videoTextureCache;
    // 创建cache
    err =  CVOpenGLESTextureCacheCreate(NULL, NULL, _context, NULL, &_videoTextureCache);
    if (err != noErr) {
        NSLog(@"CVOpenGLESTextureCacheCreate failed");
        return;
    }
    // 激活纹理
    glActiveTexture(GL_TEXTURE0);
    // 创建Y纹理
    /*
     CVOpenGLESTextureCacheCreateTextureFromImage
     功能:根据CVImageBuffer创建CVOpenGlESTexture 纹理对象
     参数1: 内存分配器,kCFAllocatorDefault
     参数2: 纹理缓存.纹理缓存将管理纹理的纹理缓存对象
     参数3: sourceImage.
     参数4: 纹理属性.默认给NULL
     参数5: 目标纹理,GL_TEXTURE_2D
     参数6: 指定纹理中颜色组件的数量(GL_RGBA, GL_LUMINANCE, GL_RGBA8_OES, GL_RG, and GL_RED (NOTE: 在 GLES3 使用 GL_R8 替代 GL_RED).)
     参数7: 帧宽度
     参数8: 帧高度
     参数9: 格式指定像素数据的格式
     参数10: 指定像素数据的数据类型,GL_UNSIGNED_BYTE
     参数11: planeIndex
     参数12: 纹理输出新创建的纹理对象将放置在此处。
     */
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RED_EXT,
                                                       width,
                                                       height,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &_lumaTexture);
    if (err != noErr) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        return;
    }
    
    //2.配置亮度纹理属性
    //绑定纹理.
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    //配置纹理放大/缩小过滤方式以及纹理围绕S/T环绕方式
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // 配置UV
    if (planeCount == 2)
    {
        // UV-plane.
        //激活UV-plane纹理
        glActiveTexture(GL_TEXTURE1);
        //4.创建UV-plane纹理
        /*
         CVOpenGLESTextureCacheCreateTextureFromImage
         功能:根据CVImageBuffer创建CVOpenGlESTexture 纹理对象
         参数1: 内存分配器,kCFAllocatorDefault
         参数2: 纹理缓存.纹理缓存将管理纹理的纹理缓存对象
         参数3: sourceImage.
         参数4: 纹理属性.默认给NULL
         参数5: 目标纹理,GL_TEXTURE_2D
         参数6: 指定纹理中颜色组件的数量(GL_RGBA, GL_LUMINANCE, GL_RGBA8_OES, GL_RG, and GL_RED (NOTE: 在 GLES3 使用 GL_R8 替代 GL_RED).)
         参数7: 帧宽度
         参数8: 帧高度
         参数9: 格式指定像素数据的格式
         参数10: 指定像素数据的数据类型,GL_UNSIGNED_BYTE
         参数11: planeIndex
         参数12: 纹理输出新创建的纹理对象将放置在此处。
         */
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           width / 2,
                                                           height / 2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        //5.绑定纹理
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
        //6.配置纹理放大/缩小过滤方式以及纹理围绕S/T环绕方式
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    // 设置视口
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    glViewport(0, 0, _backingWidth, _backingHeight);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glUseProgram(self.program);
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    // YUV -> RGB 矩阵
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_COVERSEION_MATRIX], 1, GL_FALSE, _preferredConversion);
    // 根据视频的方向和纵横比设置四边形顶点
    CGRect viewBounds = self.bounds;
    CGSize contentSize = CGSizeMake(width, height);
    /*
     AVMakeRectWithAspectRatioInsideRect
     功能: 返回一个按比例缩放的CGRect，该CGRect保持由边界CGRect内的CGSize指定的纵横比
     参数1:希望保持的宽高比或纵横比
     参数2:填充的rect
     */
    CGRect vertexSamplingRect  = AVMakeRectWithAspectRatioInsideRect(contentSize, viewBounds);
    //标准化规模
    // 计算标准化的四边形坐标以将帧绘制到其中
    //标准化采样大小
    CGSize normalizedSamplingSize = CGSizeMake(0, 0 );
    //标准化规模
    CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width / viewBounds.size.width, vertexSamplingRect.size.height / viewBounds.size.height);
    // 规范化四元顶点
    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.height / normalizedSamplingSize.width;
    }else {
        normalizedSamplingSize.width = cropScaleAmount.width/cropScaleAmount.height;
        normalizedSamplingSize.height = 1.0;
    }
    /*
     四顶点数据定义了我们绘制像素缓冲区的二维平面区域。
     使用（-1，-1）和（1,1）分别作为左下角和右上角坐标形成的顶点数据覆盖整个屏幕。
     */
    GLfloat quadVertexData [] = {
        -1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        -1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
        normalizedSamplingSize.width,
        normalizedSamplingSize.height,
    };
    // 设置顶点坐标
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    /*
     纹理顶点的设置使我们垂直翻转纹理。这使得我们的左上角原点缓冲区匹配OpenGL的左下角纹理坐标系
     */
    CGRect textureSamplingRect = CGRectMake(0, 0, 1, 1);
    GLfloat quadTextureData[] =  {
        CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect)
    };
    //更新纹理坐标属性值
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    // 绘制
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
    //清理纹理,方便下一帧纹理显示
    [self cleanUpTextures];
    // 定期纹理缓存刷新每帧
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
    
    if(_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
}

- (void)setupGL
{
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.program);
    glUniform1i(uniforms[UNIFROM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniform1i(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_COVERSEION_MATRIX], 1, GL_FALSE, _preferredConversion);
}

- (void)setupBuffers
{
    // 取消深度测试
    glDisable(GL_DEPTH_TEST);
    // 打开ATTRIB_VERTEX属性
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 2, NULL);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 2, NULL);
    [self createBuffers];
}

- (void)createBuffers
{
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    // 绑定渲染缓冲区
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
    // 设置渲染缓冲区的尺寸
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    // 检查framebuffer状态
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make compele framebuffer");
    }
}

//清理纹理(Y纹理,UV纹理)
- (void) cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
}

#pragma mark - shader compilation

//片元着色器代码
const GLchar *shader_fsh = (const GLchar*)"varying highp vec2 texCoordVarying;"
"precision mediump float;"
"uniform sampler2D SamplerY;"
"uniform sampler2D SamplerUV;"
"uniform mat3 colorConversionMatrix;"
"void main()"
"{"
"    mediump vec3 yuv;"
"    lowp vec3 rgb;"
//   Subtract constants to map the video range start at 0
"    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));"
"    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));"
"    rgb = colorConversionMatrix * yuv;"
"    gl_FragColor = vec4(rgb, 1);"
"}";

//顶点着色器代码
const GLchar *shader_vsh = (const GLchar*)"attribute vec4 position;"
"attribute vec2 texCoord;"
"uniform float preferredRotation;"
"varying vec2 texCoordVarying;"
"void main()"
"{"
"    mat4 rotationMatrix = mat4(cos(preferredRotation), -sin(preferredRotation), 0.0, 0.0,"
"                               sin(preferredRotation),  cos(preferredRotation), 0.0, 0.0,"
"                               0.0,                        0.0, 1.0, 0.0,"
"                               0.0,                        0.0, 0.0, 1.0);"
"    gl_Position = position * rotationMatrix;"
"    texCoordVarying = texCoord;"
"}";

- (BOOL)loadShaders
{
    GLuint vertShader = 0, fragShader = 0;
    
    // 创建着色program.
    self.program = glCreateProgram();
    
    //编译顶点着色器
    if(![self compileShaderString:&vertShader type:GL_VERTEX_SHADER shaderString:shader_vsh]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    //编译片元着色器
    if(![self compileShaderString:&fragShader type:GL_FRAGMENT_SHADER shaderString:shader_fsh]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // 附着顶点着色器到program.
    glAttachShader(self.program, vertShader);
    
    // 附着片元着色器到program.
    glAttachShader(self.program, fragShader);
    
    // 绑定属性位置。这需要在链接之前完成.(让ATTRIB_VERTEX/ATTRIB_TEXCOORD 与position/texCoord产生连接)
    glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    
    // Link the program.
    if (![self linkProgram:self.program]) {
        NSLog(@"Failed to link program: %d", self.program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (self.program) {
            glDeleteProgram(self.program);
            self.program = 0;
        }
        
        return NO;
    }
    
    //获取uniform的位置
    //Y亮度纹理
    uniforms[UNIFROM_Y] = glGetUniformLocation(self.program, "SamplerY");
    //UV色量纹理
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    //旋转角度preferredRotation
    uniforms[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(self.program, "preferredRotation");
    //YUV->RGB
    uniforms[UNIFORM_COLOR_COVERSEION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(self.program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(self.program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

//编译shader
- (BOOL)compileShaderString:(GLuint *)shader type:(GLenum)type shaderString:(const GLchar*)shaderString
{
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &shaderString, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    GLint status = 0;
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL
{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
        NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }
    
    const GLchar *source = (GLchar *)[sourceString UTF8String];
    
    return [self compileShaderString:shader type:type shaderString:source];
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (void)dealloc
{
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        return;
    }
    
    [self cleanUpTextures];
    
    if(_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    
    if (self.program) {
        glDeleteProgram(self.program);
        self.program = 0;
    }
    if(_context) {
        _context = nil;
    }
    
}

@end

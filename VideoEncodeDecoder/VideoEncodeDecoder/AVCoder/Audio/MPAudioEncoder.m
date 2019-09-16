//
//  MPAudioEncoder.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/11.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPAudioEncoder.h"
#import "MPAVConfig.h"
#import <AudioToolbox/AudioToolbox.h>

@interface MPAudioEncoder ()

@property (nonatomic, strong) dispatch_queue_t encoderQueue;
@property (nonatomic, strong) dispatch_queue_t callbackQueue;
/// 音频转换器对象
@property (nonatomic, assign) AudioConverterRef audioConverter;
/// PCM缓冲区
@property (nonatomic, assign) char *pcmBuffer;
/// PCM缓冲区大小
@property (nonatomic, assign) size_t pcmBufferSize;

@end

@implementation MPAudioEncoder

- (instancetype)initWithConfig: (MPAudioConfig *)config
{
    self = [super init];
    _config = config;
    _encoderQueue = dispatch_queue_create("acc.hard.encoder.queue", DISPATCH_QUEUE_SERIAL);
    _callbackQueue = dispatch_queue_create("acc.hard.callback.queue", DISPATCH_QUEUE_SERIAL);
    _audioConverter = NULL;
    _pcmBuffer = NULL;
    _pcmBufferSize = 0;
    return self;
}

/// 编码
- (void)encodeAudioSampleBuffer: (CMSampleBufferRef)sampleBuffer
{
    CFRetain(sampleBuffer);
    if (!_audioConverter) {
        // 创建音频转换器
        [self setupEncoderWithSampleBuffer:sampleBuffer];
    }
    dispatch_async(self.encoderQueue, ^{
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        CFRetain(blockBuffer);
        // 获取blockBuffer中音频大小及数据地址
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &_pcmBufferSize, &_pcmBuffer);
        if (status != kCMBlockBufferNoErr) {
            NSLog(@"CMBlockBufferGetDataPointer failed");
            return;
        }
        // 设置aacBuffer为0
        uint8_t *pcmBuffer = malloc(_pcmBufferSize);
        memset(pcmBuffer, 0, _pcmBufferSize);
        
        // 将pcmBuffer数据填充都outAudioBufferList对象中
        AudioBufferList outAudioBufferList = {0};
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = (uint32_t)_config.channelCount;
        outAudioBufferList.mBuffers[0].mDataByteSize = (uint32_t)_pcmBufferSize;
        outAudioBufferList.mBuffers[0].mData = pcmBuffer;
        
        UInt32 outputDataPacketSize = 1
        /*
         1、音频转换器
         2、回调函数，提供转换音频数据的回调函数，当转换器
         准备好接收新的输入数据时，会重复调用此回调
         3、调用者self
         4、输出缓冲区大小
         5、需要转换的音频数据
         6、输出包信息
         */;
        status = AudioConverterFillComplexBuffer(_audioConverter, aacEncodeInputDataProc, (__bridge void *)self, &outputDataPacketSize, &outAudioBufferList, NULL);
        if (status == noErr) {
            // 获取数据
            NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            free(pcmBuffer);
            // 添加ADTS头，如果想要获取裸流，请忽略添加ADTS头，写入文件时，必须添加
//            NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
//            NSMutableData *fullData = [NSMutableData dataWithCapacity:adtsHeader.length + rawAAC.length];
//            [fullData appendData:adtsHeader];
//            [fullData appendData:rawAAC];
            dispatch_async(self.callbackQueue, ^{
                [self.delegate audioEncoderCallback:rawAAC];
            });
        }else {
            NSLog(@"AudioConverterFillComplexBuffer failed");
        }
        CFRelease(blockBuffer);
        CFRelease(sampleBuffer);
    });
}

/// 配置音频编码参数
- (void)setupEncoderWithSampleBuffer: (CMSampleBufferRef)sampleBuffer
{
    // 获取输入参数
    AudioStreamBasicDescription inputDesc = *CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer));
    // 设置输出参数
    AudioStreamBasicDescription outputDesc = {0};
    // 采样率
    outputDesc.mSampleRate = (Float64)_config.sampleRate;
    // 输出格式
    outputDesc.mFormatID = kAudioFormatMPEG4AAC;
    // 如果设为0，代表无损编码
    outputDesc.mFormatFlags = kMPEG4Object_AAC_LC;
    // 自己确定每个packet的大小
    outputDesc.mBytesPerPacket = 0;
    // 每一个packet帧数 aac-1024
    outputDesc.mFramesPerPacket = 1024;
    // 每一帧大小
    outputDesc.mBytesPerFrame = 0;
    // 输出声道数
    outputDesc.mChannelsPerFrame = (uint32_t)_config.channelCount;
    // 数据帧中每个通道的采样位数
    outputDesc.mBitsPerChannel = 0;
    // 对齐方式0（8字节对齐）
    outputDesc.mReserved = 0;
    // 填充输出相关信息
    UInt32 outDesSize = sizeof(outputDesc);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &outDesSize, &outputDesc);
    // 获取编码器的描述信息，只能传入software
    AudioClassDescription *audioClassDesc = [self getAudioCalssDescriptionWithType:outputDesc.mFormatID fromManufacture:kAppleSoftwareAudioCodecManufacturer];
    // 创建converter
    // 参数1、输入音频格式描述
    // 参数2、输出音频格式描述
    // 参数3、class desc数量
    // 参数4、class desc
    // 参数5、创建的解码器
    OSStatus status =  AudioConverterNewSpecific(&inputDesc, &outputDesc, 1, audioClassDesc, &_audioConverter);
    if (status != noErr) {
        NSLog(@"AudioConverterNewSpecific failed status=%d", (int)status);
        return;
    }
    // 设置编码质量
    UInt32 temp = kAudioConverterQuality_High;
    AudioConverterSetProperty(_audioConverter, kAudioConverterCodecQuality, sizeof(temp), &temp);
    // 设置比特率
    uint32_t audioBitrate = (uint32_t)self.config.bitrate;
    uint32_t audioBitrateSize = sizeof(audioBitrate);
    status = AudioConverterSetProperty(_audioConverter, kAudioConverterEncodeBitRate, audioBitrateSize, &audioBitrate);
    if (status != noErr) {
        NSLog(@"设置比特率失败");
        return;
    }
    
}

- (AudioClassDescription *)getAudioCalssDescriptionWithType: (AudioFormatID)type fromManufacture: (uint32_t)manufacture
{
    static AudioClassDescription desc;
    UInt32 encoderSpecifix = type;
    // 满足AAC编码器的总大小
    UInt32 size;
    /*
     1、编码器类型
     2、类型描述大小
     3、类型描述
     4、大小
     */
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifix), &encoderSpecifix, &size);
    if (status != noErr) {
        NSLog(@"AudioFormatGetPropertyInfo failed");
        return nil;
    }
    // 计算aac编码器的个数
    unsigned int count = size / sizeof(AudioClassDescription);
    // 创建一个包含count个编码器的数组
    AudioClassDescription description[count];
    // 将满足aac编码的编码器的信息写入数组
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifix), &encoderSpecifix, &size, &description);
    if (status != noErr) {
        NSLog(@"AudioFormatGetProperty failed");
        return nil;
    }
    for (unsigned int i = 0; i < count; i++) {
        if (type == description[i].mSubType &&
            manufacture == description[i].mManufacturer) {
            desc = description[i];
            return &desc;
        }
    }
    return nil;
}

OSStatus aacEncodeInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription * _Nullable *outDataPacketDescription, void *inUserData)
{
    //获取self
    MPAudioEncoder *aacEncoder = (__bridge MPAudioEncoder *)(inUserData);
    
    //判断pcmBuffsize大小
    if (!aacEncoder.pcmBufferSize) {
        *ioNumberDataPackets = 0;
        return  - 1;
    }
    
    //填充
    ioData->mBuffers[0].mData = aacEncoder.pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = (uint32_t)aacEncoder.pcmBufferSize;
    ioData->mBuffers[0].mNumberChannels = (uint32_t)aacEncoder.config.channelCount;
    
    //填充完毕,则清空数据
    aacEncoder.pcmBufferSize = 0;
    *ioNumberDataPackets = 1;
    return noErr;
}


/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  AAC ADtS头
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*)adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 4;  //3： 48000 Hz、4：44.1KHz、8: 16000 Hz、11: 8000 Hz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF;    // 11111111      = syncword
    packet[1] = (char)0xF9;    // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

- (void)dealloc {
    if (_audioConverter) {
        AudioConverterDispose(_audioConverter);
        _audioConverter = NULL;
    }
    
}

@end

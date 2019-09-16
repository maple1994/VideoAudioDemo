//
//  MPAudioDecoder.m
//  VideoEncodeDecoder
//
//  Created by Maple on 2019/9/11.
//  Copyright © 2019 Maple. All rights reserved.
//

#import "MPAudioDecoder.h"
#import <AudioToolbox/AudioToolbox.h>
#import "MPAVConfig.h"

typedef struct {
    char *data;
    UInt32 size;
    UInt32 channelCount;
    AudioStreamPacketDescription packetDesc;
} MPAudioUserData;

@interface MPAudioDecoder ()

@property (nonatomic, strong) NSCondition *converterCond;
@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@property (nonatomic, strong) dispatch_queue_t callbackQueue;
@property (nonatomic, assign) AudioConverterRef audioConverter;
@property (nonatomic, assign) char *aacBuffer;
@property (nonatomic, assign) UInt32 aacBufferSize;
@property (nonatomic, assign) AudioStreamPacketDescription *packetDesc;


@end

@implementation MPAudioDecoder

//解码器回调函数
static OSStatus AudioDecoderConverterComplexInputDataProc(  AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,  AudioStreamPacketDescription **outDataPacketDescription,  void *inUserData) {
    
    
    MPAudioUserData *audioDecoder = (MPAudioUserData *)(inUserData);
    if (audioDecoder->size <= 0) {
        ioNumberDataPackets = 0;
        return -1;
    }
    
    //填充数据
    *outDataPacketDescription = &audioDecoder->packetDesc;
    (*outDataPacketDescription)[0].mStartOffset = 0;
    (*outDataPacketDescription)[0].mDataByteSize = audioDecoder->size;
    (*outDataPacketDescription)[0].mVariableFramesInPacket = 0;
    
    ioData->mBuffers[0].mData = audioDecoder->data;
    ioData->mBuffers[0].mDataByteSize = audioDecoder->size;
    ioData->mBuffers[0].mNumberChannels = audioDecoder->channelCount;
    
    return noErr;
}

- (instancetype)initWithConfig:(MPAudioConfig *)config
{
    self = [super init];
    _config = config;
    _decodeQueue = dispatch_queue_create("aac.hard.decode.queue", DISPATCH_QUEUE_SERIAL);
    _callbackQueue = dispatch_queue_create("aac.hard.decode.queue", DISPATCH_QUEUE_SERIAL);
    _audioConverter = NULL;
    _aacBufferSize = 0;
    _aacBuffer = NULL;
    AudioStreamPacketDescription desc = {0};
    _packetDesc = &desc;
    [self setupDecoder];
    return self;
}

- (void)decodeAudioAACData:(NSData *)aacData
{
    if (!_audioConverter) {
        return;
    }
    dispatch_async(self.decodeQueue, ^{
        MPAudioUserData userData = {0};
        userData.channelCount = (UInt32)self.config.channelCount;
        userData.data = (char *)[aacData bytes];
        userData.size = (UInt32)aacData.length;
        userData.packetDesc.mDataByteSize = (UInt32)aacData.length;
        userData.packetDesc.mStartOffset = 0;
        userData.packetDesc.mVariableFramesInPacket = 0;
        
        // 输出大小和packet个数
        UInt32 pcmBufferSize = (UInt32)(2048 * self.config.channelCount);
        UInt32 pcmDataPacketSize = 2014;
        uint8_t *pcmBuffer = malloc(pcmBufferSize);
        memset(pcmBuffer, 0, pcmBufferSize);
        
        // 输出buffer
        AudioBufferList outAudioBufferList = {0};
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = (uint32_t)self.config.channelCount;
        outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32)pcmBufferSize;
        outAudioBufferList.mBuffers[0].mData = pcmBuffer;
        AudioStreamPacketDescription outputPacketDesc = {0};
        OSStatus status = AudioConverterFillComplexBuffer(_audioConverter, AudioDecoderConverterComplexInputDataProc, &userData, &pcmDataPacketSize, &outAudioBufferList, &outputPacketDesc);
        if (status != noErr) {
            NSLog(@"Decoder failed");
            return;
        }
        //如果获取到数据
        if (outAudioBufferList.mBuffers[0].mDataByteSize > 0) {
            NSData *rawData = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            dispatch_async(self.callbackQueue, ^{
                [self.delegate audioDecodeCallback:rawData];
            });
        }
        free(pcmBuffer);
    });
}

- (void)setupDecoder
{
    // 输出参数pcm
    AudioStreamBasicDescription outputAudioDesc = {0};
    // 采样率
    outputAudioDesc.mSampleRate = (Float64)_config.sampleRate;
    // 输出频道
    outputAudioDesc.mChannelsPerFrame = (UInt32)_config.channelCount;
    // 输出格式
    outputAudioDesc.mFormatID = kAudioFormatLinearPCM;
    // 编码 1 2
    outputAudioDesc.mFormatFlags = (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
    // 每个packet帧数
    outputAudioDesc.mFramesPerPacket = 1;
    // 数据帧中每个通道的采样位数
    outputAudioDesc.mBitsPerChannel = 16;
    // 每一帧大小（采样位数 / 8 * 声道数）
    outputAudioDesc.mBytesPerFrame = outputAudioDesc.mBitsPerChannel / 8 * outputAudioDesc.mFramesPerPacket;
    // 每个packet大小 (帧大小 * 帧数)
    outputAudioDesc.mBytesPerPacket = outputAudioDesc.mBytesPerFrame * outputAudioDesc.mFramesPerPacket;
    // 对齐方式，0（8位对齐）
    outputAudioDesc.mReserved = 0;
    // 输入参数aac
    AudioStreamBasicDescription inputAudioDesc = {0};
    inputAudioDesc.mSampleRate = (Float64)_config.sampleRate;
    inputAudioDesc.mFormatID = kAudioFormatMPEG4AAC;
    inputAudioDesc.mFormatFlags = kMPEG4Object_AAC_LC;
    inputAudioDesc.mFramesPerPacket = 1024;
    inputAudioDesc.mChannelsPerFrame = (UInt32)_config.channelCount;
    
    // 填充输出相关信息
    UInt32 inDesSize = sizeof(inputAudioDesc);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &inDesSize, &inputAudioDesc);
    
    // 获取解码器的描述信息
    AudioClassDescription *audioClassDesc = [self getAudioCalssDescriptionWithType:outputAudioDesc.mFormatID fromManufacture:kAppleSoftwareAudioCodecManufacturer];
    OSStatus status = AudioConverterNewSpecific(&inputAudioDesc, &outputAudioDesc, 1, audioClassDesc, &_audioConverter);
    if (status != noErr) {
        NSLog(@"AudioConverterNewSpecific failed");
    }
}

- (AudioClassDescription *)getAudioCalssDescriptionWithType: (AudioFormatID)type fromManufacture: (uint32_t)manufacture
{
    
    static AudioClassDescription desc;
    UInt32 decoderSpecific = type;
    //获取满足AAC解码器的总大小
    UInt32 size;
    /**
     参数1：编码器类型（解码）
     参数2：类型描述大小
     参数3：类型描述
     参数4：大小
     */
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Decoders, sizeof(decoderSpecific), &decoderSpecific, &size);
    if (status != noErr) {
        NSLog(@"Error！：硬解码AAC get info 失败, status= %d", (int)status);
        return nil;
    }
    //计算aac解码器的个数
    unsigned int count = size / sizeof(AudioClassDescription);
    //创建一个包含count个解码器的数组
    AudioClassDescription description[count];
    //将满足aac解码的解码器的信息写入数组
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(decoderSpecific), &decoderSpecific, &size, &description);
    if (status != noErr) {
        NSLog(@"Error！：硬解码AAC get propery 失败, status= %d", (int)status);
        return nil;
    }
    for (unsigned int i = 0; i < count; i++) {
        if (type == description[i].mSubType && manufacture == description[i].mManufacturer) {
            desc = description[i];
            return &desc;
        }
    }
    return nil;
}

- (void)dealloc {
    if (_audioConverter) {
        AudioConverterDispose(_audioConverter);
        _audioConverter = NULL;
    }
    
}

@end

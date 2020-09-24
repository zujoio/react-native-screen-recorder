//
//  ASScreenRecorder.m
//  ScreenRecorder
//
//  Created by Alan Skipp on 23/04/2014.
//  Copyright (c) 2014 Alan Skipp. All rights reserved.
//

#import "ASScreenRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <UIKit/UIKit.h>

@interface ASScreenRecorder(){
BOOL isStartAudio;
}
@property (strong, nonatomic) AVAssetWriter *videoWriter;
@property (strong, nonatomic) AVAssetWriterInput *videoWriterInput;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *avAdaptor;
@property (strong, nonatomic) CADisplayLink *displayLink;
@property (strong, nonatomic) NSDictionary *outputBufferPoolAuxAttributes;

@property (nonatomic) AVCaptureDeviceInput *audioCaptureInput;
@property (nonatomic) AVAssetWriterInput *audioInput;
@property (nonatomic) AVCaptureAudioDataOutput *audioCaptureOutput;
@property (nonatomic) AVCaptureSession *captureSession;
@property (nonatomic) NSDictionary *audioSettings;

@property (nonatomic) CMTime firstAudioTimeStamp;
@property (nonatomic) NSDate *startedAt;

@property (nonatomic) CFTimeInterval firstTimeStamp;
@property (nonatomic) BOOL isRecording;
@property (nonatomic) bool stopRequested;
@property (strong, nonatomic) NSMutableArray *pauseResumeTimeRanges;

@end

@implementation ASScreenRecorder
{
    dispatch_queue_t _audio_capture_queue;
    dispatch_queue_t _render_queue;
    dispatch_queue_t _append_pixelBuffer_queue;
    dispatch_semaphore_t _frameRenderingSemaphore;
    dispatch_semaphore_t _pixelAppendSemaphore;
    
    CGSize _viewSize;
    CGFloat _scale;
    CGColorSpaceRef _rgbColorSpace;
    CVPixelBufferPoolRef _outputBufferPool;
}

#pragma mark - initializers

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static ASScreenRecorder *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _viewSize = [UIApplication sharedApplication].delegate.window.bounds.size;
        _scale = [UIScreen mainScreen].scale;
        // record half size resolution for retina iPads
        if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) && _scale > 1) {
            _scale = 1.0;
        }
        _isRecording = NO;
        _stopRequested = NO;
        _append_pixelBuffer_queue = dispatch_queue_create("ASScreenRecorder.append_queue", DISPATCH_QUEUE_SERIAL);
        _render_queue = dispatch_queue_create("ASScreenRecorder.render_queue", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_render_queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        _frameRenderingSemaphore = dispatch_semaphore_create(1);
        _pixelAppendSemaphore = dispatch_semaphore_create(1);
         [self setUpAudioCapture];

    }
    return self;
}

#pragma mark - public

-  (void)setViewToCapture:(UIView *)viewToCapture 
{
    _viewSize = viewToCapture.bounds.size;
    viewToCapture = viewToCapture;
}

- (void)setVideoURL:(NSURL *)videoURL
{
    NSAssert(!_isRecording, @"videoURL can not be changed whilst recording is in progress");
    _videoURL = videoURL;
}

- (BOOL)startRecording
{
    // if (!_isRecording) {
    //     [self setUpWriter];
    //     _isRecording = (_videoWriter.status == AVAssetWriterStatusWriting);
    //     _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(writeVideoFrame)];
    //     [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    // }
    if (!_isRecording) {
        [_captureSession startRunning];
    }
    return _isRecording;
}

- (void)pauseRecording
{
    // if (_displayLink.paused) {
    //     return;
    // }
    
    // if (!self.pauseResumeTimeRanges) {
    //     self.pauseResumeTimeRanges = [NSMutableArray new];
    // }
    
    // [self.pauseResumeTimeRanges addObject:@(_displayLink.timestamp + 0.001)]; //adding a small delay
    
    _displayLink.paused = YES;
}

- (void)resumeRecording
{
    // if (_displayLink && _displayLink.isPaused) {
        _displayLink.paused = NO;
    // }
}

- (void)stopRecordingWithCompletion:(VideoCompletionBlock)completionBlock;
{
    if (_isRecording) {
        [_captureSession stopRunning];
        _isRecording = NO;
        _stopRequested = YES;
        _displayLink.paused = NO;
        [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [self completeRecordingSession:completionBlock];
        self.pauseResumeTimeRanges = nil;
    }
}

- (BOOL)isPaused
{
    return _displayLink.paused;
}

- (void)setPaused:(BOOL)paused
{
    [self pauseRecording];
}

#pragma mark - private

-(void)setUpWriter
{
    _rgbColorSpace = CGColorSpaceCreateDeviceRGB();

    NSDictionary *bufferAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                       (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                                       (id)kCVPixelBufferWidthKey : @(_viewSize.width * _scale),
                                       (id)kCVPixelBufferHeightKey : @(_viewSize.height  * _scale),
                                       (id)kCVPixelBufferBytesPerRowAlignmentKey : @(_viewSize.width * _scale * 4),
                                    //    (id)kCVPixelBufferExtendedPixelsTopKey:@(40),
                                    //    (id)kCVPixelBufferExtendedPixelsBottomKey:@(40)
                                       };
    
    _outputBufferPool = NULL;
    CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)(bufferAttributes), &_outputBufferPool);
    
    
    NSError* error = nil;
    _videoWriter = [[AVAssetWriter alloc] initWithURL:self.videoURL ?: [self tempFileURL]
                                             fileType:AVFileTypeQuickTimeMovie
                                                error:&error];
    NSParameterAssert(_videoWriter);
    
    NSInteger pixelNumber = _viewSize.width * _viewSize.height * _scale;
    NSDictionary* videoCompression = @{AVVideoAverageBitRateKey: @(pixelNumber * 11.4)};
    
    NSDictionary* videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                                    AVVideoWidthKey: [NSNumber numberWithInt:_viewSize.width*_scale],
                                    AVVideoHeightKey: [NSNumber numberWithInt:_viewSize.height*_scale],
                                    AVVideoCompressionPropertiesKey: videoCompression,
                                    };
    
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    NSParameterAssert(_videoWriterInput);
    
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    _videoWriterInput.transform = [self videoTransformForDeviceOrientation];
    
    _avAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput sourcePixelBufferAttributes:nil];
    
    [_videoWriter addInput:_videoWriterInput];
    
    _audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:_audioSettings];
    _audioInput.expectsMediaDataInRealTime = YES;

    NSParameterAssert([_videoWriter canAddInput:_audioInput]);
    [_videoWriter addInput:_audioInput];

    [_videoWriter startWriting];
    [_videoWriter startSessionAtSourceTime:CMTimeAdd(_firstAudioTimeStamp, CMTimeMake(0.0, 1000.0))];
}

- (CGAffineTransform)videoTransformForDeviceOrientation
{
    CGAffineTransform videoTransform;
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationLandscapeLeft:
            videoTransform = CGAffineTransformMakeRotation(-M_PI_2);
            break;
        case UIDeviceOrientationLandscapeRight:
            videoTransform = CGAffineTransformMakeRotation(M_PI_2);
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            videoTransform = CGAffineTransformMakeRotation(M_PI);
            break;
        default:
            videoTransform = CGAffineTransformIdentity;
    }
    return videoTransform;
}

- (NSURL*)tempFileURL
{
    NSString *outputPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/screenCapture.mp4"];
    [self removeTempFilePath:outputPath];
    return [NSURL fileURLWithPath:outputPath];
}

- (void)removeTempFilePath:(NSString*)filePath
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError* error;
        if ([fileManager removeItemAtPath:filePath error:&error] == NO) {
            NSLog(@"Could not delete old recording:%@", [error localizedDescription]);
        }
    }
}

- (void)completeRecordingSession:(VideoCompletionBlock)completionBlock;
{
    dispatch_async(_render_queue, ^{
        dispatch_sync(_append_pixelBuffer_queue, ^{
            dispatch_sync(_audio_capture_queue, ^{
            [_audioInput markAsFinished];
            [_videoWriterInput markAsFinished];
            [_videoWriter finishWritingWithCompletionHandler:^{
                
                void (^completion)(void) = ^() {
                    [self cleanup];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completionBlock) completionBlock();
                    });
                };
                
                if (self.videoURL) {
                    completion();
                } else {
                    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                    [library writeVideoAtPathToSavedPhotosAlbum:_videoWriter.outputURL completionBlock:^(NSURL *assetURL, NSError *error) {
                        if (error) {
                            NSLog(@"Error copying video to camera roll:%@", [error localizedDescription]);
                        } else {
                            [self removeTempFilePath:_videoWriter.outputURL.path];
                            completion();
                        }
                    }];
                }

                // void (^completion)(NSURL *url) = ^(NSURL *url) {
                //   [self cleanup];
                //   dispatch_async(dispatch_get_main_queue(), ^{
                //       if (completionBlock) completionBlock(url);
                //   });
                //  };
              
                // if (self.videoURL) {
                //     completion(self.videoURL);
                // } else {
                //     completion(_videoWriter.outputURL);
                // }
            }];
        });
    });
    });
}

- (void)cleanup
{
    self.avAdaptor = nil;
    self.videoWriterInput = nil;
    self.videoWriter = nil;
    self.firstTimeStamp = 0;
    
    self.startedAt = nil;
    self.firstAudioTimeStamp = kCMTimeZero;

    self.outputBufferPoolAuxAttributes = nil;
    CGColorSpaceRelease(_rgbColorSpace);
    CVPixelBufferPoolRelease(_outputBufferPool);
}

- (void)writeVideoFrame
{
    // throttle the number of frames to prevent meltdown
    // technique gleaned from Brad Larson's answer here: http://stackoverflow.com/a/5956119
    if (dispatch_semaphore_wait(_frameRenderingSemaphore, DISPATCH_TIME_NOW) != 0) {
        return;
    }
    dispatch_async(_render_queue, ^{
        if (![_videoWriterInput isReadyForMoreMediaData] &&  _displayLink.paused == NO) return;
        
        if (!self.firstTimeStamp) {
            self.firstTimeStamp = _displayLink.timestamp;
        }
        CFTimeInterval elapsed = (_displayLink.timestamp - self.firstTimeStamp);
       if (self.pauseResumeTimeRanges.count) {
            for (int i = 0; i < self.pauseResumeTimeRanges.count; i += 2) {
                double pausedTime = [self.pauseResumeTimeRanges[i] doubleValue];
                double resumeTime = [self.pauseResumeTimeRanges[i+1] doubleValue];
                elapsed -= resumeTime - pausedTime;
            }
        }
  CMTime time = CMTimeAdd(self->_firstAudioTimeStamp, CMTimeMakeWithSeconds(elapsed, 1000));

        // CMTime time = CMTimeMakeWithSeconds(elapsed, 1000);  
        CVPixelBufferRef pixelBuffer = NULL;
        CGContextRef bitmapContext = [self createPixelBufferAndBitmapContext:&pixelBuffer];
        
        if (self.delegate) {
            [self.delegate writeBackgroundFrameInContext:&bitmapContext];
        }
        // draw each window into the context (other windows include UIKeyboard, UIAlert)
        // FIX: UIKeyboard is currently only rendered correctly in portrait orientation
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIGraphicsPushContext(bitmapContext); {
                for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                   CGRect rect = CGRectMake(0, 0, _viewSize.width, _viewSize.height);
                    UIEdgeInsets contentInsets = UIEdgeInsetsMake(-100, 0,-101, 0);
 
                    // CGRect result = UIEdgeInsetsInsetRect(rect, contentInsets);
                    [window drawViewHierarchyInRect:UIEdgeInsetsInsetRect(rect, contentInsets) afterScreenUpdates:NO];
                }
            } UIGraphicsPopContext();
        });
        
        // append pixelBuffer on a async dispatch_queue, the next frame is rendered whilst this one appends
        // must not overwhelm the queue with pixelBuffers, therefore:
        // check if _append_pixelBuffer_queue is ready
        // if it’s not ready, release pixelBuffer and bitmapContext
        if (dispatch_semaphore_wait(_pixelAppendSemaphore, DISPATCH_TIME_NOW) == 0) {
            dispatch_async(_append_pixelBuffer_queue, ^{
                BOOL success = [_avAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
                if (!success) {
                    NSLog(@"Warning: Unable to write buffer to video");
                }
                CGContextRelease(bitmapContext);
                CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                CVPixelBufferRelease(pixelBuffer);
                
                dispatch_semaphore_signal(_pixelAppendSemaphore);
            });
        } else {
            CGContextRelease(bitmapContext);
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            CVPixelBufferRelease(pixelBuffer);
        }
        
        dispatch_semaphore_signal(_frameRenderingSemaphore);
    });
}

- (CGContextRef)createPixelBufferAndBitmapContext:(CVPixelBufferRef *)pixelBuffer
{
    CVPixelBufferPoolCreatePixelBuffer(NULL, _outputBufferPool, pixelBuffer);
    CVPixelBufferLockBaseAddress(*pixelBuffer, 0);
    
    CGContextRef bitmapContext = NULL;
    bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(*pixelBuffer),
                                          CVPixelBufferGetWidth(*pixelBuffer),
                                          CVPixelBufferGetHeight(*pixelBuffer),
                                          8, CVPixelBufferGetBytesPerRow(*pixelBuffer), _rgbColorSpace,
                                          kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                          );
    CGContextScaleCTM(bitmapContext, _scale, _scale);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, _viewSize.height);
    CGContextConcatCTM(bitmapContext, flipVertical);

    return bitmapContext;
}
#pragma mark - audio recording

- (void)setUpAudioCapture
{
    NSError *error;

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (device && device.connected)
    NSLog(@"Connected Device: %@", device.localizedName);
    else
    {
    NSLog(@"AVCaptureDevice Failed");
    return;
    }

    // add device inputs
    _audioCaptureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!_audioCaptureInput)
    {
    NSLog(@"AVCaptureDeviceInput Failed");
    return;
    }
    if (error)
    {
    NSLog(@"%@", error);
    return;
    }

    // add output for audio
    _audioCaptureOutput = [[AVCaptureAudioDataOutput alloc] init];
    if (!_audioCaptureOutput)
    {
    NSLog(@"AVCaptureMovieFileOutput Failed");
    return;
    }

    _audio_capture_queue = dispatch_queue_create("AudioCaptureQueue", NULL);
    [_audioCaptureOutput setSampleBufferDelegate:self queue:_audio_capture_queue];

    _captureSession = [[AVCaptureSession alloc] init];
    if (!_captureSession)
    {
    NSLog(@"AVCaptureSession Failed");
    return;
    }
    _captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    if ([_captureSession canAddInput:_audioCaptureInput])
    [_captureSession addInput:_audioCaptureInput];
    else
    {
    NSLog(@"Failed to add input device to capture session");
    return;
    }
    if ([_captureSession canAddOutput:_audioCaptureOutput])
    [_captureSession addOutput:_audioCaptureOutput];
    else
    {
    NSLog(@"Failed to add output device to capture session");
    return;
    }

    _audioSettings = [_audioCaptureOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie];

    NSLog(@"Audio capture session running");
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (captureOutput == _audioCaptureOutput) {
    NSLog(@"capture");
    if (_startedAt == nil) {
    isStartAudio = true;
    _startedAt = [NSDate date];
    _firstAudioTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    // [self setUpWriter];
    // self.isRecording = (self->_videoWriter.status == AVAssetWriterStatusWriting);
    // self->_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(writeVideoFrame)];
    // [self->_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self setUpWriter];
        _isRecording = (_videoWriter.status == AVAssetWriterStatusWriting);
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(writeVideoFrame)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    
    if (_isRecording && [_audioInput isReadyForMoreMediaData]) {
        [_audioInput appendSampleBuffer:sampleBuffer];
    }
    }
}

@end
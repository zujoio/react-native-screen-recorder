#import "RNScreenRecorder.h"
#import <React/RCTLog.h>
#import "ASScreenRecorder.h"
@implementation RNScreenRecorder

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(start)
{
  RCTLogInfo(@"started!");
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
  
  if (!recorder.isRecording) {
    [recorder startRecording];
    RCTLogInfo(@"Start recording");
  }
}

RCT_EXPORT_METHOD(pause)
{
  RCTLogInfo(@"started!");
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
  
  if (recorder.isPaused) {
    [recorder pauseRecording];
  }
}

RCT_EXPORT_METHOD(resume)
{
  RCTLogInfo(@"started!");
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
  
  if (!recorder.isPaused) {
    [recorder resumeRecording];
  }
}

RCT_EXPORT_METHOD(isPaused)
{
  RCTLogInfo(@"started!");
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
    [recorder isPaused];
}

RCT_EXPORT_METHOD(stop)
{
  RCTLogInfo(@"started!");
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
  
  if (recorder.isRecording) {
    [recorder stopRecordingWithCompletion:^{
      RCTLogInfo(@"Finished recording");
    }];
  }
}
@end
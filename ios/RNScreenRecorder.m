#import "RNScreenRecorder.h"
#import <React/RCTLog.h>
#import "ASScreenRecorder.h"
#import "AppDelegate.h"
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
#import "RNVideoEditor.h"
#define DEGREES_TO_RADIANS(degrees)((M_PI * degrees)/180)

@implementation RNVideoEditor

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}
RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(merge:(NSArray *)fileNames
                  errorCallback:(RCTResponseSenderBlock)failureCallback
                  callback:(RCTResponseSenderBlock)successCallback) {

    NSLog(@"%@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));

    [self MergeVideos:fileNames callback:successCallback];
}

- (void)MergeVideos:(NSArray *)fileNames callback:(RCTResponseSenderBlock)successCallback {
        NSUInteger count = 0;
        AVAsset *firstVideo = [AVAsset assetWithURL:[NSURL fileURLWithPath:[fileNames objectAtIndex:0]]];
        NSArray* firstVideoTracks = [firstVideo tracks];
        AVAssetTrack* firstTrackFirstVideo = [firstVideoTracks objectAtIndex:0];
        CGSize firstVideoSize = firstTrackFirstVideo.naturalSize;
        CGAffineTransform firstVideoTransform = firstTrackFirstVideo.preferredTransform;

        AVMutableComposition *mutableComposition = [[AVMutableComposition alloc] init];
        AVMutableCompositionTrack *videoCompositionTrack = [mutableComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                           preferredTrackID:kCMPersistentTrackID_Invalid];

        AVMutableCompositionTrack *audioTrack = [mutableComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                           preferredTrackID:kCMPersistentTrackID_Invalid];

        __block NSMutableArray *instructions = [[NSMutableArray alloc] init];
        __block CMTime time = kCMTimeZero;
        __block AVMutableVideoComposition *mutableVideoComposition = [AVMutableVideoComposition videoComposition];
        __block int32_t commontimescale = 600;

        // Create one layer instruction.  We have one video track, and there should be one layer instruction per video track.
        AVMutableVideoCompositionLayerInstruction *videoLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoCompositionTrack];

        for (id object in fileNames)
            {
            AVAsset *asset = [AVAsset assetWithURL: [NSURL fileURLWithPath:object]];

            CMTime cliptime = CMTimeConvertScale(asset.duration, commontimescale, kCMTimeRoundingMethod_QuickTime);

            NSLog(@"%s: Number of tracks: %lu", __PRETTY_FUNCTION__, (unsigned long)[[asset tracks] count]);
            AVAssetTrack *assetTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
            CGSize naturalSize = assetTrack.naturalSize;

            NSError *error;
            //insert the video from the assetTrack into the composition track
            [videoCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, cliptime)
                                           ofTrack:assetTrack
                                            atTime:time
                                             error:&error];

            [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, cliptime)
                                                    ofTrack:[[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0]
                                                     atTime:time
                                                      error:&error];
            if (error) {
                NSLog(@"%s: Error - %@", __PRETTY_FUNCTION__, error.debugDescription);
            }

            CGAffineTransform transform = assetTrack.preferredTransform;

            //set the layer to have this videos transform at the time that this video starts
            if (naturalSize.width == transform.tx && naturalSize.height == transform.ty) {
                NSLog(@"VIDEO ORIENTATION -> UIInterfaceOrientationLandscapeRight");
                 //these videos have the identity transform, yet they are upside down.
                 //we need to rotate them by M_PI radians (180 degrees) and shift the video back into place

                 CGAffineTransform rotateTransform = CGAffineTransformMakeRotation(DEGREES_TO_RADIANS(180));
                 CGAffineTransform translateTransform = CGAffineTransformMakeTranslation(naturalSize.width, naturalSize.height);
                 [videoLayerInstruction setTransform:CGAffineTransformConcat(rotateTransform, translateTransform) atTime:time];
            } else if (transform.tx == 0 && transform.ty == 0) {
                NSLog(@"VIDEO ORIENTATION -> UIInterfaceOrientationLandscapeLeft");
                [videoLayerInstruction setTransform:transform atTime:time];
            } else if (transform.tx == 0 && transform.ty == naturalSize.width) {
                NSLog(@"VIDEO ORIENTATION -> UIInterfaceOrientationPortraitUpsideDown");
                [videoLayerInstruction setTransform:transform atTime:time];
            } else {
                NSLog(@"VIDEO ORIENTATION -> UIInterfaceOrientationPortrait");
                [videoLayerInstruction setTransform:transform atTime:time];
            }

            // time increment variables
            time = CMTimeAdd(time, cliptime);
            count++;
        };

        // the main instruction set - this is wrapping the time
        AVMutableVideoCompositionInstruction *videoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        videoCompositionInstruction.timeRange = CMTimeRangeMake(kCMTimeZero,mutableComposition.duration); //make the instruction last for the entire composition
        videoCompositionInstruction.layerInstructions = @[videoLayerInstruction];
        [instructions addObject:videoCompositionInstruction];
        mutableVideoComposition.instructions = instructions;

        // set the frame rate to 30fps
        mutableVideoComposition.frameDuration = CMTimeMake(1, 30);

        //set the rendersize for the video we're about to write
        if (firstVideoSize.width == firstVideoTransform.tx && firstVideoSize.height == firstVideoTransform.ty) {
            NSLog(@"First video -> UIInterfaceOrientationLandscapeRight");
            mutableVideoComposition.renderSize = CGSizeMake(firstTrackFirstVideo.naturalSize.width,firstTrackFirstVideo.naturalSize.height);
        } else if (firstVideoTransform.tx == 0 && firstVideoTransform.ty == 0) {
            NSLog(@"First video -> UIInterfaceOrientationLandscapeLeft");
            mutableVideoComposition.renderSize = CGSizeMake(firstTrackFirstVideo.naturalSize.width,firstTrackFirstVideo.naturalSize.height);
        } else if (firstVideoTransform.tx == 0 && firstVideoTransform.ty == firstVideoSize.width) {
            NSLog(@"First video -> UIInterfaceOrientationPortraitUpsideDown");
            mutableVideoComposition.renderSize = CGSizeMake(firstTrackFirstVideo.naturalSize.height, firstTrackFirstVideo.naturalSize.width);
        } else {
            NSLog(@"First video -> UIInterfaceOrientationPortrait");
            mutableVideoComposition.renderSize = CGSizeMake(firstTrackFirstVideo.naturalSize.height, firstTrackFirstVideo.naturalSize.width);
        }

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        int number = arc4random_uniform(10000);
        NSString * outputFile = [documentsDirectory stringByAppendingFormat:@"/export_%i.mov",number];

        //let the rendersize of the video composition dictate size.  use quality preset here
        AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:mutableComposition
                                                                          presetName:AVAssetExportPresetHighestQuality];

        exporter.outputURL = [NSURL fileURLWithPath:outputFile];
        //Set the output file type
        exporter.outputFileType = @"com.apple.quicktime-movie";
        exporter.shouldOptimizeForNetworkUse = YES;
        exporter.videoComposition = mutableVideoComposition;

        [exporter exportAsynchronouslyWithCompletionHandler:^{
            switch ([exporter status])
            {
                case AVAssetExportSessionStatusFailed:
                    break;

                case AVAssetExportSessionStatusCancelled:
                    break;

                case AVAssetExportSessionStatusCompleted:
                    successCallback(@[@"merge video complete", outputFile]);
                    break;

                default:
                    break;
            }
        }];
    }

- (NSString*) applicationDocumentsDirectory
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}
@end

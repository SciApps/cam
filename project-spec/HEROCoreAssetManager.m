//
//  HEROCoreAssetManager.m
//  CoreAssetManager
//
//  Created by mrnuku on 2016. 01. 17..
//  Copyright © 2016. mrnuku. All rights reserved.
//

#import "HEROCoreAssetManager.h"
#import "CoreAssetItemImage.h"
#import "CoreAssetWorkerDescriptor.h"

@implementation HEROCoreAssetManager

- (instancetype)init {
    self = [super init];
    
    if (self) {
        [self registerThreadForClass:[CoreAssetItemImage class]];
        [self enumerateImageAssetsForClass:[CoreAssetItemImage class] withSubpath:@"images"];
    }
    
    return self;
}

- (void)fetchImageAssetListFromImages:(NSArray *)images startDownload:(BOOL)startDownload {
    Class clss = [CoreAssetItemImage class];
    
    CoreAssetWorkerDescriptor *worker = [self.threadDescriptors objectForKey:NSStringFromClass(clss)];
    
    @synchronized (worker) {
        for (MCK_Image* oneElement in images) {
            NSString *assetName = oneElement.imageUrl;
            CoreAssetItemImage *temp = [worker.cachedDict objectForKey:assetName];
            
            if (!temp) {
                // check if its already in normal download list
                temp = [worker.normalDict objectForKey:assetName];
                
                // if in normal list, do nothing
                if (temp) {
                    continue;
                }
                
                // check if its already in prior list
                temp = [worker.priorDict objectForKey:assetName];
                
                // if in prior list, do nothing
                if (temp) {
                    continue;
                }
                
                // if not, create new, add to the normal list
                temp = [CoreAssetItemImage new];
                temp.assetName = assetName;
                [worker.normalDict setObject:temp forKey:assetName];
            }
        }
        
        [worker invalidateNormalList];
    }
    
    if (startDownload) {
        _terminateDownloads = NO;
        worker.backgroundFetchMode = NO;
        [worker resume];
        [self performSelectorOnMainThread:@selector(resumeDownloadForClass:) withObject:clss waitUntilDone:NO];
    }
}

@end

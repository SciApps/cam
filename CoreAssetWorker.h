//
//  CoreAssetWorker.h
//  FinTech
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetItemNormal.h"
#import "CoreAssetURLConnection.h"

extern NSString *kCoreAssetWorkerAssetItem;
extern NSString *kCoreAssetWorkerAssetData;
extern NSString *kCoreAssetWorkerAssetPostprocessedData;

@protocol CoreAssetWorkerDelegate <NSObject>

@optional
- (void)finishedDownloadingAsset:(NSDictionary *)assetDict;
- (void)failedDownloadingAsset:(NSDictionary *)assetDict;

@end

@interface CoreAssetWorker : NSObject

@property (atomic, assign) NSUInteger spinCount;
@property (atomic, assign) BOOL terminateSpin;
@property (atomic, assign) BOOL terminate;
@property (atomic, assign) BOOL useSession;
@property (atomic, assign) BOOL useCURL;
@property (atomic, assign) CFTimeInterval timeAll;
@property (atomic, assign) CFTimeInterval timeCurrentStart;
@property (atomic, assign) CFTimeInterval timeCurrent;
@property (atomic, assign) size_t sizeAll;
@property (atomic, assign) size_t sizeCurrent;
@property (atomic, assign) CGFloat bandwith;
@property (nonatomic, weak) NSObject<CoreAssetWorkerDelegate>* delegate;

- (void)stop;
- (void)resume;
- (void)downloadAsset:(CoreAssetItemNormal *)asset;
- (BOOL)isBusy;

@end

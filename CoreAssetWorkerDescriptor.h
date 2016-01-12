//
//  CoreAssetWorkerDescriptor.h
//  FinTech
//
//  Created by Bálint Róbert on 14/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetWorker.h"

@interface CoreAssetWorkerDescriptor : NSObject <CoreAssetWorkerDelegate>

@property (nonatomic, strong) NSMutableDictionary *normalDict;
@property (nonatomic, strong) NSMutableDictionary *priorDict;
@property (nonatomic, strong) NSMutableDictionary *cachedDict;
@property (nonatomic, strong) NSNumber *successfullDownloadsNum;
@property (nonatomic, assign, readonly) NSUInteger numWorkers;
@property (nonatomic, assign) BOOL backgroundFetchMode;

@property (nonatomic, weak) NSObject<CoreAssetWorkerDelegate>* delegate;

+ (instancetype)descriptorWithClass:(Class)clss;

- (BOOL)hasDownloadLists;
- (void)continueDownload:(NSUInteger)workerLimit;

- (void)stop;
- (void)resume;
- (BOOL)isBusy;

- (void)removeAssetFromCache:(CoreAssetItemNormal *)assetItem;

/// call this when new prior dict avaible to make a new sorted internal list with prior level
- (void)invalidatePriorList;
- (void)invalidateNormalList;

@end

//
//  CoreAssetWorkerDescriptor.m
//  FinTech
//
//  Created by Bálint Róbert on 14/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import "CoreAssetWorkerDescriptor.h"
#import "NSArray+Union.h"

@interface CoreAssetWorkerDescriptor ()

@property (nonatomic, strong) Class workerClass;
@property (nonatomic, strong) NSMutableArray *workers;
@property (nonatomic, strong) NSMutableArray *workersAssetItem;
@property (nonatomic, assign) NSUInteger numWorkers;
@property (nonatomic, strong) NSEnumerator *priorEnumerator;
@property (nonatomic, assign) BOOL terminate;

@end

@implementation CoreAssetWorkerDescriptor

+ (instancetype)descriptorWithClass:(Class)clss {
    CoreAssetWorkerDescriptor *descriptor = [CoreAssetWorkerDescriptor new];
    
    if (descriptor) {
        descriptor.workerClass = clss;
        
        descriptor.numWorkers = [clss workerThreads];
        
        for (NSUInteger i = 0; i < descriptor.numWorkers; i++) {
            CoreAssetWorker *worker = [CoreAssetWorker new];
            worker.delegate = descriptor;
            [descriptor.workers addObject:worker];
            [descriptor.workersAssetItem addObject:[NSNull null]];
        }
    }
    
    return descriptor;
}

- (instancetype)init {
    self = [super init];
    
    if (self) {
        _normalDict = [NSMutableDictionary new];
        _priorDict = [NSMutableDictionary new];
        _cachedDict = [NSMutableDictionary new];
        _workers = [NSMutableArray new];
        _workersAssetItem = [NSMutableArray new];
        _successfullDownloadsNum = @(0);
        _backgroundFetchMode = NO;
        _terminate = NO;
    }
    
    return self;
}

- (BOOL)hasDownloadLists {
    return (_priorDict.count + _normalDict.count) > 0;
}

- (void)matchDictWithWorkers:(NSMutableDictionary *)dict {
    NSArray* containerUnion = [_workersAssetItem arrayOfUnionObjectsWithDictionary:dict useObjectsFromDictionary:NO];
    
    for (CoreAssetItemNormal *intersectedItem in containerUnion) {
        CoreAssetItemNormal *obsoleteItem = [dict objectForKey:intersectedItem.assetName];
        
        for (id handler in obsoleteItem.assetCompletionHandlers) {
            [intersectedItem addCompletionHandler:handler];
        }
        
        [dict removeObjectForKey:intersectedItem.assetName];
    }
}

- (void)invalidatePriorList {
    @synchronized(self) {
        [self matchDictWithWorkers:_priorDict];
        
        NSArray *sortedPriorList = [_priorDict.objectEnumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(CoreAssetItemNormal *obj1, CoreAssetItemNormal *obj2) {
            return (obj1.priorLevel == obj2.priorLevel) ? [obj1.assetName localizedStandardCompare:obj2.assetName] : ((obj1.priorLevel > obj2.priorLevel) ? NSOrderedAscending : ((obj1.priorLevel < obj2.priorLevel) ? NSOrderedDescending : NSOrderedSame));
        }];
        
        _priorEnumerator = sortedPriorList.objectEnumerator;
    }
}

- (void)invalidateNormalList {
    @synchronized (self) {
        [self matchDictWithWorkers:_normalDict];
    }
}

- (void)continueDownload:(NSUInteger)workerLimit withEnumerator:(NSEnumerator *)enumerator andDict:(NSMutableDictionary *)dict {
    CoreAssetItemNormal *assetItem;
    
    while (workerLimit) {
        
        for (NSUInteger i = 0; i < _workers.count; i++) {
            
            id obj = [_workersAssetItem objectAtIndex:i];
            
            if (obj == [NSNull null]) {
                CoreAssetWorker *worker = [_workers objectAtIndex:i];
                
                assetItem = enumerator.nextObject;
                
                while (assetItem && ([_workersAssetItem containsObject:assetItem] || [_cachedDict objectForKey:assetItem.assetName])) {
                    assetItem = enumerator.nextObject;
                }
                
                if (!assetItem && dict == _priorDict) {
                    dict = _normalDict;
                    enumerator = dict.objectEnumerator;
                    assetItem = enumerator.nextObject;
                    
                    while (assetItem && ([_workersAssetItem containsObject:assetItem] || [_cachedDict objectForKey:assetItem.assetName])) {
                        assetItem = enumerator.nextObject;
                    }
                }
                
                if (assetItem) {
                    [_workersAssetItem replaceObjectAtIndex:i withObject:assetItem];
                    [dict removeObjectForKey:assetItem.assetName];
                    
                    if (dict != _priorDict) {
                        enumerator = dict.objectEnumerator;
                    }
                    
                    [worker downloadAsset:assetItem];
                }
                
                workerLimit--;
                break;
            }
        }
    }
}

- (void)continueDownload:(NSUInteger)workerLimit {
    @synchronized(self) {
        if (_terminate) {
            return;
        }
        
        NSEnumerator *enumerator = nil;
        NSMutableDictionary *dict = _priorDict;
        
        for (NSUInteger i = 0; i < _workers.count && workerLimit; i++) {
            
            id obj = [_workersAssetItem objectAtIndex:i];
            
            if (obj != [NSNull null]) {
                workerLimit--;
            }
        }
        
        if (_priorDict.count) {
            enumerator = _priorEnumerator;
        }
        else if (!enumerator && _normalDict.count) {
            dict = _normalDict;
            enumerator = dict.objectEnumerator;
        }
        
        [self continueDownload:workerLimit withEnumerator:enumerator andDict:dict];
    }
}

- (void)stop {
    @synchronized(self) {
        _terminate = YES;
        
        [_workersAssetItem removeAllObjects];
        
        for (CoreAssetWorker *worker in _workers) {
            [worker stop];
            [_workersAssetItem addObject:[NSNull null]];
        }
    }
}

- (void)resume {
    @synchronized(self) {
        _terminate = NO;
        
        for (CoreAssetWorker *worker in _workers) {
            [worker resume];
        }
        
        [self continueDownload:_numWorkers];
    }
}

- (BOOL)isBusy {
    @synchronized(self) {
        
        for (id obj in _workersAssetItem) {
            
            if (obj != [NSNull null]) {
                return YES;
            }
        }
    }
    
    return NO;
}

- (void)removeAssetFromCache:(CoreAssetItemNormal *)assetItem {
    if ([_cachedDict objectForKey:assetItem.assetName]) {
        [_cachedDict removeObjectForKey:assetItem.assetName];
    }
    else {
        TestLog(@"removeAssetFromCache: not in cache");
    }
    
    [assetItem removeStoredFile];
}

#pragma mark - CoreAssetWorkerDelegate methods

- (void)finishedDownloadingAsset:(NSDictionary *)assetDict {
    @synchronized(self) {
        
        CoreAssetItemNormal *assetItem = [assetDict objectForKey:kCoreAssetWorkerAssetItem];
        NSUInteger workerIdx = [_workersAssetItem indexOfObject:assetItem];
        
        if (workerIdx == NSNotFound) {
            TestLog(@"finishedDownloadingAsset: fatal error");
        }
        else {
            [_workersAssetItem replaceObjectAtIndex:workerIdx withObject:[NSNull null]];
        }
        
        NSData *connectionData = [assetDict objectForKey:kCoreAssetWorkerAssetData];
        if (connectionData.length) {
            [_cachedDict setObject:assetItem forKey:assetItem.assetName];
        }
        else {
            [assetItem removeStoredFile];
        }
        
        if (!_backgroundFetchMode) {
            [self continueDownload:_numWorkers];
        }
        
        if ([_delegate respondsToSelector:@selector(finishedDownloadingAsset:)]) {
            [_delegate finishedDownloadingAsset:assetDict];
        }
    }
}

- (void)failedDownloadingAsset:(NSDictionary *)assetDict {
    @synchronized(self) {
        
        CoreAssetItemNormal *assetItem = [assetDict objectForKey:kCoreAssetWorkerAssetItem];
        NSUInteger workerIdx = [_workersAssetItem indexOfObject:assetItem];
        
        if (workerIdx == NSNotFound) {
            TestLog(@"finishedDownloadingAsset: fatal error");
        }
        else {
            [_workersAssetItem replaceObjectAtIndex:workerIdx withObject:[NSNull null]];
        }
        
        if (!_backgroundFetchMode) {
            [self continueDownload:_numWorkers];
        }
        
        if ([_delegate respondsToSelector:@selector(failedDownloadingAsset:)]) {
            [_delegate failedDownloadingAsset:assetDict];
        }
    }
}

@end

//
//  CoreAssetManager.m
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import "CoreAssetManager.h"
#import "CoreAssetWorker.h"
#import "CoreAssetWorkerDescriptor.h"
#import "CoreAssetItemImage.h"
#import "UtilMacros.h"

#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>

@interface CoreAssetManager() <CoreAssetWorkerDelegate>

@property (nonatomic, strong) NSMutableDictionary   *threadDescriptorsPriv;
@property (nonatomic, assign) BOOL                  authenticationInProgress;
@property (nonatomic, strong) NSOperationQueue      *cachedOperationQueue;
@property (nonatomic) dispatch_semaphore_t          backgroundFetchLock;
@property (nonatomic) SCNetworkReachabilityRef      reachability;

- (void)_processReachabilityFlags:(SCNetworkReachabilityFlags)flags;

@end

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
#pragma unused (target, flags)
    NSCAssert(info != NULL, @"info was NULL in ReachabilityCallback");
    NSCAssert([(__bridge NSObject*) info isKindOfClass:CoreAssetManager.class], @"info was wrong class in ReachabilityCallback");
    
    CoreAssetManager* cam = (__bridge CoreAssetManager *)info;
    [cam _processReachabilityFlags:flags];
}

@implementation CoreAssetManager

@synthesize classList = _classList;

/*static CoreAssetManager *instance;

+ (instancetype)sharedInstance {
    if (!instance) {
        instance = [CoreAssetManager new];
    }
    
    return instance;
}*/

- (NSDictionary *)threadDescriptors {
    return _threadDescriptorsPriv.copy;
}

- (instancetype)init {
    self = [super init];
    
    if (self) {
        _classList = [NSMutableArray new];
        _threadDescriptorsPriv = [NSMutableDictionary new];
        _authenticationInProgress = NO;
        _cachedOperationQueue = [NSOperationQueue new];
        _cachedOperationQueue.name = @"cachedOperationQueue";
        _delegates = [OKOMutableWeakArray new];
        _terminateDownloads = NO;
#ifdef USE_CACHE
        _dataCache = [NSCache new];
        _dataCacheAges = [NSMutableDictionary new];
#endif
        _loginCondition = [NSCondition new];
        _loginCount = @0;
        _loginSuccessful = @0;
        [self _initReachability];
    }
    
    return self;
}

- (void)dealloc {
    SCNetworkReachabilityUnscheduleFromRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    CFRelease(_reachability);
    _reachability = NULL;
}

- (void)_initReachability {
    NSString *hostName = [self reachabilityHost];
    
    if (hostName.length) {
        _reachability = SCNetworkReachabilityCreateWithName(NULL, hostName.UTF8String);
    }
    else {
        struct sockaddr_in zeroAddress;
        bzero(&zeroAddress, sizeof(zeroAddress));
        zeroAddress.sin_len = sizeof(zeroAddress);
        zeroAddress.sin_family = AF_INET;
        
        _reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (struct sockaddr *)&zeroAddress);
    }
    
    SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    
    if (SCNetworkReachabilitySetCallback(_reachability, ReachabilityCallback, &context)) {
        if (SCNetworkReachabilityScheduleWithRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode)) {
            TestLog(@"SCNetworkReachabilityScheduleWithRunLoop success");
        }
        else {
            TestLog(@"SCNetworkReachabilityScheduleWithRunLoop failed");
        }
    }
    else {
        TestLog(@"SCNetworkReachabilitySetCallback failed");
    }
    
#if TARGET_IPHONE_SIMULATOR
    self.networkStatus = CAMReachableViaWiFi;
#else
    SCNetworkReachabilityFlags flags;
    
    if (SCNetworkReachabilityGetFlags(_reachability, &flags)) {
        [self _processReachabilityFlags:flags];
    }
#endif
}

- (void)_processReachabilityFlags:(SCNetworkReachabilityFlags)flags {
    if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
        self.networkStatus = CAMNotReachable;
        [self _printReachabilityStatus];
        return;
    }
    
    CoreAssetManagerNetworkStatus networkStatus = CAMNotReachable;
    
    if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
        networkStatus = CAMReachableViaWiFi;
    }
    
    if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0)) {
        if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
            networkStatus = CAMReachableViaWiFi;
        }
    }
    
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
        networkStatus = CAMReachableViaWWAN;
    }
    
    self.networkStatus = networkStatus;
    [self _printReachabilityStatus];
}

- (void)_printReachabilityStatus {
    NSArray<NSString *> *networkStatusLabels = @[@"CAMNotReachable", @"CAMReachableViaWiFi", @"CAMReachableViaWWAN"];
    TestLog(@"CoreAssetManager.Reachability: %@", [networkStatusLabels objectAtIndex:self.networkStatus]);
}

+ (NSArray *)listFilesInCacheDirectoryWithExtension:(NSString *)extension withSubpath:(NSString *)subpath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *assetPath = [CoreAssetItemNormal assetStorageDirectory];
    
    if (subpath) {
        assetPath = [assetPath stringByAppendingPathComponent:[subpath stringByAppendingString:@"/"]];
    }
    
    NSMutableArray *list = [NSMutableArray new];
    for (NSString *path in [fileManager enumeratorAtPath:assetPath]) {
        if ([[path pathExtension] isEqualToString:extension])
            [list addObject:path];
    }
    
    return [NSArray arrayWithArray:list];
}

+ (void)removeAllAssetFromCache {
    NSString *assetPath = [CoreAssetItemNormal assetStorageDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *fileArray = [fileManager contentsOfDirectoryAtPath:assetPath error:nil];
    
    for (NSString *filename in fileArray)  {
        TestLog(@"%@",filename);
        
        if ([filename rangeOfString:@".pdf"].location != NSNotFound || [filename rangeOfString:@".png"].location != NSNotFound || [filename rangeOfString:@".jpg"].location != NSNotFound) {
            [fileManager removeItemAtPath:[assetPath stringByAppendingPathComponent:filename] error:NULL];
        }
    }
}

#pragma mark public interfaces

- (void)stopAllDownloads {
    _terminateDownloads = YES;
    
    for (Class clss in _classList) {
        CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
        
        if ([worker isBusy]) {
            TestLog(@"stopAllDownloads: killing busy worker... class: '%@'", NSStringFromClass(clss));
        }
        
        [worker stop];
    }
    
    _authenticationInProgress = NO;
}

- (void)removeAllCaches {
#ifdef USE_CACHE
    [_dataCache removeAllObjects];
#endif
    
    for (Class clss in _classList) {
        CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
        
        @synchronized (worker) {
            [worker.cachedDict enumerateKeysAndObjectsUsingBlock:^(NSString *assetName, CoreAssetItemNormal *assetItem, BOOL *stop) {
                [assetItem removeStoredFile];
            }];
            
            TestLog(@"removeAllCaches: [1st] removed number of assets: %li in class: '%@'", (long)worker.cachedDict.count, NSStringFromClass(clss));
            
            [worker.normalDict removeAllObjects];
            [worker invalidateNormalList];
            [worker.priorDict removeAllObjects];
            [worker invalidatePriorList];
            [worker.cachedDict removeAllObjects];
        }
    }
    
    // TOO: FIXME
    [self enumerateImageAssetsForClass:[CoreAssetItemImage class] withSubpath:@"images"];
    
    for (Class clss in _classList) {
        CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
        
        @synchronized (worker) {
            [worker.cachedDict enumerateKeysAndObjectsUsingBlock:^(NSString *assetName, CoreAssetItemNormal *assetItem, BOOL *stop) {
                [assetItem removeStoredFile];
            }];
            
            TestLog(@"removeAllCaches: [2nd] removed number of assets: %li in class: '%@'", (long)worker.cachedDict.count, NSStringFromClass(clss));
            
            [worker.normalDict removeAllObjects];
            [worker invalidateNormalList];
            [worker.priorDict removeAllObjects];
            [worker invalidatePriorList];
            [worker.cachedDict removeAllObjects];
        }
    }
    
#ifdef DEBUG
    // extra check
    // TOO: FIXME
    [self enumerateImageAssetsForClass:[CoreAssetItemImage class] withSubpath:@"images"];
    
    NSUInteger faultyRemoveCount = 0;
    
    for (Class clss in _classList) {
        CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
        
        TestLog(@"removeAllCaches: faultyRemoveCount: %li in class: '%@'", (long)worker.cachedDict.count, NSStringFromClass(clss));
        
        @synchronized (worker) {
            faultyRemoveCount += worker.cachedDict.count;
        }
    }
    
    if (faultyRemoveCount) {
        [CoreAssetManager removeAllAssetFromCache];
    }
#endif
}

- (BOOL)_isAssetMemoryCacheAgeExpired:(CoreAssetItemNormal *)assetItem {
    NSDate *modDate = [_dataCacheAges objectForKey:assetItem.cacheIdentifier];
    
    if (assetItem.cacheMaxAge > 0 && modDate) {
        NSTimeInterval delta = [modDate timeIntervalSinceNow];
        return delta < -assetItem.cacheMaxAge;
    }
    
    return assetItem.cacheMaxAge > 0;
}

- (id)fetchAssetDataClass:(Class)clss forAssetName:(id)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler {
    
    //CFTimeInterval startTime = CACurrentMediaTime();
    
    if (!assetName) {
        return nil;
    }
    
    _terminateDownloads = NO;
    
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    if (!worker) {
        TestLog(@"fetchAssetDataClass: class not registered '%@'", NSStringFromClass(clss));
        return nil;
    }
    
    @synchronized (worker) {
        
        CoreAssetItemNormal *assetItem = [worker.cachedDict objectForKey:assetName];
        
        while (assetItem) {
#ifdef USE_CACHE
            if ([self _isAssetMemoryCacheAgeExpired:assetItem]) {
                [_dataCacheAges removeObjectForKey:assetItem.cacheIdentifier];
                [_dataCache removeObjectForKey:assetItem.cacheIdentifier];
            }
            
            id processedDataCached;
            
            if ((processedDataCached = [_dataCache objectForKey:[assetItem cacheIdentifier]])) {
                if (completionHandler) {
                    completionHandler(processedDataCached);
                }
                
                return [NSNull null];
            }
#endif
            if (assetItem.storedFileCachingAgeExpired) {
                [worker removeAssetFromCache:assetItem removeFile:!assetItem.retrieveCachedObjectOnFailure];
                break;
            }
            
            id blockCopy = [assetItem addCompletionHandler:completionHandler];
            
            /*if ([assetItem isKindOfClass:[CoreAssetItemImage class]] && PLATFORM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"4.0")) {
                NSData *cachedData = nil;
                
                @try {
                    cachedData = [assetItem load];
                }
                @catch (NSException *exception) {
                    [worker removeAssetFromCache:assetItem];
                }
                
                if (cachedData) {
                    id processedData = [assetItem postProcessData:cachedData];

#ifdef USE_CACHE
#if USE_CACHE > 1
                    if (assetItem.shouldCache) {
#endif
                        if (![processedData isKindOfClass:NSNull.class]) {
                            [_dataCache setObject:processedData forKey:[assetItem cacheIdentifier]];
                        }
#if USE_CACHE > 1
                    }
#endif
#endif
                    
                    [assetItem sendCompletionHandlerMessages:processedData];
                }
                
                return blockCopy;
            }*/
            
            [_cachedOperationQueue addOperationWithBlock:^{
                //CFTimeInterval lstartTime = CACurrentMediaTime();
                NSData *cachedData = nil;
                
                @try {
                    cachedData = [assetItem load];
                }
                @catch (NSException *exception) {
                    [worker removeAssetFromCache:assetItem removeFile:YES];
                }
                
                if (cachedData) {
                    id processedData = [assetItem postProcessData:cachedData];

#ifdef USE_CACHE
#if USE_CACHE > 1
                    if (assetItem.shouldCache) {
#endif
                        if (![processedData isKindOfClass:NSNull.class]) {
                            [_dataCache setObject:processedData forKey:[assetItem cacheIdentifier]];
                        }
#if USE_CACHE > 1
                    }
#endif
#endif
                    
                    if (![processedData isKindOfClass:[NSNull class]]) {
                        [assetItem performSelectorOnMainThread:@selector(sendCompletionHandlerMessages:) withObject:processedData waitUntilDone:NO];
                    }
                }
                
                //CFTimeInterval lendTime = CACurrentMediaTime();
                
                //TestLog(@"Load:%.1fms '%@'", (lendTime-lstartTime)*1000.0, assetItem.assetName);
            }];
            
            //CFTimeInterval endTime = CACurrentMediaTime();
            
            //TestLog(@"Search:%.1fms", (endTime-startTime)*1000.0);
            
            return blockCopy;
        }
        
        assetItem = [worker.normalDict objectForKey:assetName];
        
        if (!assetItem) {
            assetItem = [worker.priorDict objectForKey:assetName];
        }
        else {
            [worker.normalDict removeObjectForKey:assetName];
            [worker.priorDict setObject:assetItem forKey:assetName];
            [worker invalidateNormalList];
        }
        
        if (!assetItem) {
            assetItem = [clss new];
            assetItem.assetName = assetName;
            [worker.priorDict setObject:assetItem forKey:assetName];
        }
        
        assetItem.retryCount = kCoreAssetManagerFetchWithBlockRetryCount;
        
        if (assetItem.priorLevel != kCoreAssetManagerFetchWithBlockPriorLevel) {
            assetItem.priorLevel = kCoreAssetManagerFetchWithBlockPriorLevel;
            [worker invalidatePriorList];
        }
        
        id blockCopy = [assetItem addCompletionHandler:completionHandler];
        
        [worker resume];
        [self performSelectorOnMainThread:@selector(resumeDownloadForClass:) withObject:clss waitUntilDone:NO];
        
        return blockCopy;
    }
    
    //CFTimeInterval endTime = CACurrentMediaTime();
    
    //TestLog(@"Search:%.1fms", (endTime-startTime)*1000.0);
    
    return nil;
}

// TODO: integrate functions

- (id)fetchAssetDataClass:(Class)clss forAssetName:(id)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler {
    
    if (!failureHandler) {
        return [self fetchAssetDataClass:clss forAssetName:assetName withCompletionHandler:completionHandler];
    }
    
    //CFTimeInterval startTime = CACurrentMediaTime();
    
    if (!assetName) {
        return nil;
    }
    
    _terminateDownloads = NO;
    
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    if (!worker) {
        TestLog(@"fetchAssetDataClass: class not registered '%@'", NSStringFromClass(clss));
        return nil;
    }
    
    @synchronized (worker) {
        
        CoreAssetItemNormal *assetItem = [worker.cachedDict objectForKey:assetName];
        
        while (assetItem) {
#ifdef USE_CACHE
            if ([self _isAssetMemoryCacheAgeExpired:assetItem]) {
                [_dataCacheAges removeObjectForKey:assetItem.cacheIdentifier];
                [_dataCache removeObjectForKey:assetItem.cacheIdentifier];
            }
            
            id processedDataCached;
            
            if ((processedDataCached = [_dataCache objectForKey:[assetItem cacheIdentifier]])) {
                if (completionHandler) {
                    completionHandler(processedDataCached);
                }
                
                return [NSNull null];
            }
#endif
            if (assetItem.storedFileCachingAgeExpired) {
                [worker removeAssetFromCache:assetItem removeFile:!assetItem.retrieveCachedObjectOnFailure];
                break;
            }
            
            id blockCopy = [assetItem addCompletionHandler:completionHandler];
            id blockCopy2 = [assetItem addFailureHandler:failureHandler];
            
            [_cachedOperationQueue addOperationWithBlock:^{
                //CFTimeInterval lstartTime = CACurrentMediaTime();
                NSData *cachedData = nil;
                
                @try {
                    cachedData = [assetItem load];
                }
                @catch (NSException *exception) {
                    [worker removeAssetFromCache:assetItem removeFile:YES];
                }
                
                if (cachedData) {
                    id processedData = [assetItem postProcessData:cachedData];
                    
#ifdef USE_CACHE
#if USE_CACHE > 1
                    if (assetItem.shouldCache) {
#endif
                        if (![processedData isKindOfClass:NSNull.class]) {
                            [_dataCache setObject:processedData forKey:[assetItem cacheIdentifier]];
                        }
#if USE_CACHE > 1
                    }
#endif
#endif
                    
                    if (![processedData isKindOfClass:[NSNull class]]) {
                        [assetItem performSelectorOnMainThread:@selector(sendCompletionHandlerMessages:) withObject:processedData waitUntilDone:NO];
                    }
                }
                
                //CFTimeInterval lendTime = CACurrentMediaTime();
                
                //TestLog(@"Load:%.1fms '%@'", (lendTime-lstartTime)*1000.0, assetItem.assetName);
            }];
            
            //CFTimeInterval endTime = CACurrentMediaTime();
            
            //TestLog(@"Search:%.1fms", (endTime-startTime)*1000.0);
            
            return @[blockCopy, blockCopy2];
        }
        
        assetItem = [worker.normalDict objectForKey:assetName];
        
        if (!assetItem) {
            assetItem = [worker.priorDict objectForKey:assetName];
        }
        else {
            [worker.normalDict removeObjectForKey:assetName];
            [worker.priorDict setObject:assetItem forKey:assetName];
            [worker invalidateNormalList];
        }
        
        if (!assetItem) {
            assetItem = [clss new];
            assetItem.assetName = assetName;
            [worker.priorDict setObject:assetItem forKey:assetName];
        }
        
        assetItem.retryCount = kCoreAssetManagerFetchWithBlockRetryCount;
        
        if (assetItem.priorLevel != kCoreAssetManagerFetchWithBlockPriorLevel) {
            assetItem.priorLevel = kCoreAssetManagerFetchWithBlockPriorLevel;
            [worker invalidatePriorList];
        }
        
        id blockCopy = [assetItem addCompletionHandler:completionHandler];
        id blockCopy2 = [assetItem addFailureHandler:failureHandler];
        
        [worker resume];
        [self performSelectorOnMainThread:@selector(resumeDownloadForClass:) withObject:clss waitUntilDone:NO];
        
        return @[blockCopy, blockCopy2];
    }
    
    //CFTimeInterval endTime = CACurrentMediaTime();
    
    //TestLog(@"Search:%.1fms", (endTime-startTime)*1000.0);
    
    return nil;
}

+ (id)fetchImageWithName:(NSString *)assetName withCompletionHandler:(void (^)(UIImage *image))completionHandler {
    CoreAssetManager *am = [CoreAssetManager manager];
    
    return [am fetchAssetDataClass:[CoreAssetItemImage class] forAssetName:assetName withCompletionHandler:completionHandler];
}

- (NSDictionary *)getCacheDictForDataClass:(Class)clss {
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    return worker.cachedDict;
}

- (void)prioratizeAssetWithName:(NSString *)assetName forClass:(Class)clss priorLevel:(NSUInteger)priorLevel retryCount:(NSUInteger)retryCount startDownload:(BOOL)startDownload {
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    @synchronized (worker) {
        CoreAssetItemNormal *temp = [worker.cachedDict objectForKey:assetName];
        CoreAssetItemNormal *temp2 = [worker.normalDict objectForKey:assetName];
        CoreAssetItemNormal *temp3 = [worker.priorDict objectForKey:assetName];
        
        if (temp3) {
            temp3.retryCount = retryCount;
            
            if (temp3.priorLevel != priorLevel) {
                temp3.priorLevel = priorLevel;
                [worker invalidatePriorList];
            }
        }
        else if (temp2) {
            [worker.priorDict setObject:temp2 forKey:assetName];
            [worker.normalDict removeObjectForKey:assetName];
            
            temp2.retryCount = retryCount;
            temp2.priorLevel = priorLevel;
            [worker invalidateNormalList];
            [worker invalidatePriorList];
        }
        else if (!temp) {
            temp = [clss new];
            temp.assetName = assetName;
            
            [worker.priorDict setObject:temp forKey:assetName];
            [worker.normalDict removeObjectForKey:assetName];
            
            temp.retryCount = retryCount;
            temp.priorLevel = priorLevel;
            [worker invalidateNormalList];
            [worker invalidatePriorList];
        }
    }
    
    if (startDownload) {
        worker.successfullDownloadsNum = @(0);
        _terminateDownloads = NO;
        worker.backgroundFetchMode = NO;
        [worker resume];
        [self performSelectorOnMainThread:@selector(resumeDownloadForClass:) withObject:clss waitUntilDone:NO];
    }
}

#pragma mark Image related

- (void)enumerateImageAssetsForClass:(Class)clss withSubpath:(NSString *)subpath {
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    NSArray *imageList = [CoreAssetManager listFilesInCacheDirectoryWithExtension:@"png" withSubpath:subpath];
    NSArray *imageList2 = [CoreAssetManager listFilesInCacheDirectoryWithExtension:@"jpg" withSubpath:subpath];
    imageList = [imageList arrayByAddingObjectsFromArray:imageList2];
    
    @synchronized (worker) {
        for (NSString *imageFilePath in imageList) {
            CoreAssetItemImage *temp = [CoreAssetItemImage new];
            
            temp.assetName = [imageFilePath lastPathComponent];
//          temp.assetName = [[imageFilePath lastPathComponent] stringByDeletingPathExtension];
//          temp.assetName = [temp.assetName stringByReplacingOccurrencesOfString:@"IMG_" withString:@""];
            [worker.cachedDict setObject:temp forKey:temp.assetName];
        }
    }
}

#pragma mark asset class handling

- (void)registerThreadForClass:(Class)clss {
    // allocate thread
    CoreAssetWorkerDescriptor *worker = [CoreAssetWorkerDescriptor descriptorWithClass:clss];
    worker.delegate = self;
    [_threadDescriptorsPriv setObject:worker forKey:NSStringFromClass(clss)];
    
    [_classList addObject:clss];
}

- (void)removeAssetFromDownloadDict:(CoreAssetItemNormal *)assetItem andDispatchCompletionHandlersWithData:(id)assetData loadAssetData:(BOOL)load {
    Class clss = [assetItem class];
    
    //
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    NSMutableArray *removeList = [[NSMutableArray alloc] initWithCapacity:2];
    
    CoreAssetItemNormal *normalItem = [worker.normalDict objectForKey:assetItem.assetName];
    CoreAssetItemNormal *priorItem = [worker.priorDict objectForKey:assetItem.assetName];
    
    if (normalItem) {
        [worker.normalDict removeObjectForKey:assetItem.assetName];
        [removeList addObject:normalItem];
    }
    
    if (priorItem) {
        [worker.priorDict removeObjectForKey:assetItem.assetName];
        [removeList addObject:priorItem];
    }
    
    
    if (!removeList.count)
        TestLog(@"removeAssetFromDownloadList: no instances found for asset '%@' class: '%@'", assetItem.assetName, NSStringFromClass(clss));
    else if (removeList.count > 1)
        TestLog(@"removeAssetFromDownloadList: multiple instances found for asset '%@' count: %li class: '%@'", assetItem.assetName, (long)removeList.count, NSStringFromClass(clss));
    
    [removeList addObject:assetItem];
    
    for (CoreAssetItemNormal *removeItem in removeList) {
        
        if (removeItem.assetCompletionHandlers.count) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                id processedData = assetData;
                
                if(!processedData && load) {
                    NSData *cachedData = [removeItem load];
                    processedData = [removeItem postProcessData:cachedData];

#ifdef USE_CACHE
#if USE_CACHE > 1
                    if (removeItem.shouldCache) {
#endif
                        if (![processedData isKindOfClass:NSNull.class]) {
                            [_dataCache setObject:processedData forKey:[removeItem cacheIdentifier]];
                        }
#if USE_CACHE > 1
                    }
#endif
#endif
                }
                
                [removeItem performSelectorOnMainThread:@selector(sendCompletionHandlerMessages:) withObject:processedData waitUntilDone:NO];
            });
        }
    }
}

- (void)addAssetToCacheDict:(CoreAssetItemNormal *)assetItem {
    Class clss = [assetItem class];
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    [worker.cachedDict setObject:assetItem forKey:assetItem.assetName];
}

- (CoreAssetItemNormal *)getNextDownloadableAssetForClass:(Class)clss {
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    CoreAssetItemNormal *assetItem = nil;
    
    if (worker.priorDict.count)
        assetItem = [[worker.priorDict objectEnumerator] nextObject];
    
    if (!assetItem)
        assetItem = [[worker.normalDict objectEnumerator] nextObject];
    
    // terminates recursion
    if (!assetItem)
        return nil;
    
    CoreAssetItemNormal *cachedItem = [worker.cachedDict objectForKey:assetItem.assetName];
    
    // impossible case when a download finished with asset but still inside the dl list
    if (cachedItem) {
        [self removeAssetFromDownloadDict:assetItem andDispatchCompletionHandlersWithData:nil loadAssetData:YES];
        assetItem = [self getNextDownloadableAssetForClass:clss];
    }
    
    return assetItem;
}

- (void)checkDownloadState {
    NSUInteger busyWorkerCount = 0;
    
    for (Class clss in _classList) {
        CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
        busyWorkerCount += [worker isBusy];
    }
    
    //[[CoreNotificationManager sharedInstance] notifyUserAboutDownloading: busyWorkerCount > 0];
}

- (void)resumeDownloadForClass:(Class)clss {
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    if (_backgroundFetchLock && !worker.isBusy) {
        dispatch_semaphore_signal(_backgroundFetchLock);
    }
    
    if (_authenticationInProgress || _backgroundFetchLock) {
        return;
    }
    
    [worker resume];
    [worker continueDownload:worker.numWorkers];
    
    [self checkDownloadState];
}

- (void)resumeDownloadAllClass {
    for (Class clss in _classList) {
        [self resumeDownloadForClass:clss];
    }
}

#pragma mark CoreAssetWorkerDelegate methods

- (void)finishedDownloadingAsset:(NSDictionary *)assetDict {
    NSData *connectionData = [assetDict objectForKey:kCoreAssetWorkerAssetData];
    CoreAssetItemNormal *assetItem = [assetDict objectForKey:kCoreAssetWorkerAssetItem];
    id postprocessedData = [assetDict objectForKey:kCoreAssetWorkerAssetPostprocessedData];
    const char* dataBytes = connectionData.bytes;
    const char htmlHeader[] = {'<', 'h', 't', 'm', 'l', '>'};
//    const char pngHeader[] = {0x89, 'P', 'N', 'G'};
//    const char gifHeader[] = {'G', 'I', 'F', '8'};
//    const char jpgHeader[] = {0xFF, 0xD8, 0xFF}; // e0-e1 as 4th byte
//    NSError *error;
    NSDictionary *jsonResponse;
    BOOL isImageAsset = NO;
    
    Class clss = [assetItem class];
    CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
    
    if (_terminateDownloads) {
        [assetItem removeStoredFile];
        return;
    }
    else if ([assetItem isKindOfClass:[CoreAssetItemImage class]] && postprocessedData && memcmp(dataBytes, htmlHeader, sizeof(htmlHeader))) {
        //TestLog(@"finishedDownloadingAsset: png asset: '%@' class: '%@'", assetItem.assetName, NSStringFromClass(clss));
        isImageAsset = YES;
        
        if ([postprocessedData isKindOfClass:[CoreAssetItemErrorImage class]]) {
            TestLog(@"finishedDownloadingAsset: no-pic error asset: '%@' class: '%@'", assetItem.assetName, NSStringFromClass(clss));
            [worker removeAssetFromCache:assetItem removeFile:YES];
        } else {
            worker.successfullDownloadsNum = @(worker.successfullDownloadsNum.integerValue + 1);
        }
    }
    else if ([assetItem isKindOfClass:[CoreAssetItemImage class]] && postprocessedData && ![postprocessedData isKindOfClass:[NSNull class]] && memcmp(dataBytes, htmlHeader, sizeof(htmlHeader))) {
        NSDictionary* errorDict = [jsonResponse objectForKey:@"error"];
        NSString* errorCode = [errorDict objectForKey:@"code"];
        
        NSString *reasonString = [NSString stringWithFormat:@"finishedDownloadingAsset: json, error code: %@ asset: '%@' class: '%@'", errorCode, assetItem.assetName, NSStringFromClass(clss)];
        TestLog(@"%@", reasonString);
        
        if (errorCode) {
            /*ServerErrorCode code = (ServerErrorCode)[errorCode integerValue];
            
            if (code == ServerErrorCode_AuthNeeded || code == ServerErrorCode_SessionIsOver) {
                if (!authenticationInProgress) {
                    authenticationInProgress = YES;
                    [[AuthenticationManager sharedInstance] automaticLoginWithCompletionHandler:^(NSException *error) {
                        authenticationInProgress = NO;
                        [self resumeDownloadAllClass];
                    }];
                }
                return;
            }*/
            
            // any other error codes
            [self removeAssetFromDownloadDict:assetItem andDispatchCompletionHandlersWithData:nil loadAssetData:NO];
            [assetItem removeStoredFile];
            [self resumeDownloadForClass:clss];
            [assetItem sendFailureOnMainThreadToHandlers:[NSError errorWithDomain:reasonString code:0 userInfo:nil]];
            return;
        }
    }
    else if (!connectionData.length) {
        NSString *reasonString = [NSString stringWithFormat:@"finishedDownloadingAsset: unknown error asset: '%@' class: '%@' zero bytes", assetItem.assetName, NSStringFromClass(clss)];
        TestLog(@"%@", reasonString);
        //[worker removeAssetFromCache:assetItem];
        [self resumeDownloadForClass:clss];
        [assetItem sendFailureOnMainThreadToHandlers:[NSError errorWithDomain:reasonString code:0 userInfo:nil]];
        return;
    }
    else {
        NSString *reasonString = [NSString stringWithFormat:@"finishedDownloadingAsset: unknown error asset: '%@' class: '%@' bytes: '%.4s' (%.2x%.2x%.2x%.2x)", assetItem.assetName, NSStringFromClass(clss), dataBytes, (UInt8)dataBytes[0], (UInt8)dataBytes[1], (UInt8)dataBytes[2], (UInt8)dataBytes[3]];
        TestLog(@"%@", reasonString);
        [worker removeAssetFromCache:assetItem removeFile:YES];
        [self resumeDownloadForClass:clss];
        [assetItem sendFailureOnMainThreadToHandlers:[NSError errorWithDomain:reasonString code:0 userInfo:nil]];
        return;
    }
    
#ifdef USE_CACHE
#if USE_CACHE > 1
    if (assetItem.shouldCache) {
#endif
        if (![postprocessedData isKindOfClass:NSNull.class] && ![postprocessedData isKindOfClass:CoreAssetItemErrorImage.class]) {
            [_dataCache setObject:postprocessedData forKey:[assetItem cacheIdentifier]];
            [_dataCacheAges setObject:[NSDate date] forKey:[assetItem cacheIdentifier]];
        }
#if USE_CACHE > 1
    }
#endif
#endif
    
    [assetItem sendPostProcessedDataToHandlers:postprocessedData];
    [_delegates compact];
    
    if (isImageAsset) {
        
        for (NSObject<CoreAssetManagerDelegate> *delegate in _delegates) {
            
            if ([delegate respondsToSelector:@selector(cachedImageDictChanged:)]) {
                CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
                [delegate performSelectorOnMainThread:@selector(cachedImageDictChanged:) withObject:worker.cachedDict waitUntilDone:NO];
            }
        }
    }
    
    [self resumeDownloadForClass:clss];
}

- (void)failedDownloadingAsset:(NSDictionary *)assetDict {
    CoreAssetItemNormal *assetItem = [assetDict objectForKey:kCoreAssetWorkerAssetItem];
    Class clss = [assetItem class];
    
    if (assetItem.retrieveCachedObjectOnFailure) {
        [_cachedOperationQueue addOperationWithBlock:^{
            CoreAssetWorkerDescriptor *worker = [_threadDescriptorsPriv objectForKey:NSStringFromClass(clss)];
            //CFTimeInterval lstartTime = CACurrentMediaTime();
            NSData *cachedData = nil;
            
            @try {
                cachedData = [assetItem load];
            }
            @catch (NSException *exception) {
                [worker removeAssetFromCache:assetItem removeFile:YES];
            }
            
            id processedData;
            if (cachedData) {
                processedData = [assetItem postProcessData:cachedData];
            }
            
            if (![processedData isKindOfClass:[NSNull class]]) {
                [assetItem performSelectorOnMainThread:@selector(sendCompletionHandlerMessages:) withObject:processedData waitUntilDone:NO];
            }
            else {
                [assetItem sendFailureOnMainThreadToHandlers:[NSError errorWithDomain:[NSString stringWithFormat:@"failedDownloadingAsset: '%@' class: '%@' (retrieveCachedObjectOnFailure)", assetItem.assetName, NSStringFromClass(clss)] code:0 userInfo:nil]];
            }
        }];
        
        return;
    }
    
    NSString *reasonString = [NSString stringWithFormat:@"failedDownloadingAsset: '%@' class: '%@'", assetItem.assetName, NSStringFromClass(clss)];
    TestLog(@"%@", reasonString);
    
    [self resumeDownloadForClass:clss];
    [assetItem sendFailureOnMainThreadToHandlers:[NSError errorWithDomain:reasonString code:0 userInfo:nil]];
}

- (void)addWeakDelegate:(NSObject<CoreAssetManagerDelegate> *)delegate {
    [_delegates addObject:delegate];
    [_delegates compact];
}

- (void)removeWeakDelegate:(NSObject<CoreAssetManagerDelegate> *)delegate {
    [_delegates removeObject:delegate];
    [_delegates compact];
}

- (BOOL)determineLoginFailure:(id)postprocessedData {
    return NO;
}

- (void)reauthenticateWithCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler {
    completionHandler(nil);
}

- (NSString *)reachabilityHost {
    return @"";
}

- (void)performRelogin {
    NSUInteger count;
    @synchronized (_loginCount) {
        count = _loginCount.unsignedIntegerValue;
    }
    
    [_loginCondition lock];
    
    [self reauthenticateWithCompletionHandler:^(id assetData) {
        self.loginSuccessful = @1;
        [_loginCondition signal];
        [_loginCondition unlock];
    } withFailureHandler:^(NSError *reason) {
        self.loginSuccessful = @0;
        [_loginCondition signal];
        [_loginCondition unlock];
    }];
}

#pragma mark - helper methods

+ (void)disableBackupForFilePath:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    
    if (![fileURL setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error]) {
        TestLog(@"disableBackupForFilePath: an error uccured: '%@'", error.description);
    }
}

@end

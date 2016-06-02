//
//  CoreAssetManager.h
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@import util;

#define kCoreAssetManagerFetchWithBlockPriorLevel 9999
#define kCoreAssetManagerFetchWithBlockRetryCount 3
#define kCoreAssetManagerDefaultRetryCount 1

#define USE_CURL 1 // 0 - use objective-c http api, 1 - use curl
#define USE_CACHE 2 // 0 - dont use cache, 1 - cache evrything, 2 - cache controlled by asset item (shouldCache)

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSInteger {
    CAMNotReachable = 0,
    CAMReachableViaWiFi,
    CAMReachableViaWWAN
} CoreAssetManagerNetworkStatus;

typedef void (^CoreAssetManagerCompletionBlock)(id assetData);
typedef void (^CoreAssetManagerFailureBlock)(NSError *reason);

@protocol CoreAssetManagerDelegate <NSObject>

@optional
- (void)cachedImageDictChanged:(NSDictionary *)cacheDict;

@end

@interface CoreAssetManager : Manager {
@private
    NSMutableArray        *_classList;
}

@property (nonatomic, copy, readonly) NSDictionary *threadDescriptors;
@property (nonatomic, readonly) NSArray *classList;
@property (nonatomic, assign) BOOL terminateDownloads;
@property (nonatomic, strong) OKOMutableWeakArray   *delegates;
#ifdef USE_CACHE
@property (nonatomic, strong) NSCache               *dataCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *>   *dataCacheAges;
#endif
@property (nonatomic, strong) NSCondition           *loginCondition;
@property (nonatomic, strong) NSNumber              *loginCount;
@property (nonatomic, strong) NSNumber              *loginSuccessful;
@property (atomic) CoreAssetManagerNetworkStatus    networkStatus;

- (void)registerThreadForClass:(Class)clss;

/// killing all download worker threads
- (void)stopAllDownloads;
/// remving all cached file
- (void)removeAllCaches;

- (void)resumeDownloadAllClass;
- (void)performRelogin;

- (_Nullable id)fetchAssetDataClass:(Class)clss forAssetName:(id)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler;
- (_Nullable id)fetchAssetDataClass:(Class)clss forAssetName:(id)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler;

/// for priorizing user stuff
- (void)prioratizeAssetWithName:(NSString *)assetName forClass:(Class)clss priorLevel:(NSUInteger)priorLevel retryCount:(NSUInteger)retryCount startDownload:(BOOL)startDownload;

// example: NSDictionary *stuff = [[CoreAssetManager sharedInstance] getCacheDictForDataClass:[CoreAssetItemPDF class]];
- (NSDictionary *)getCacheDictForDataClass:(Class)clss;

- (void)addWeakDelegate:(NSObject<CoreAssetManagerDelegate> *)delegate;
- (void)removeWeakDelegate:(NSObject<CoreAssetManagerDelegate> *)delegate;

+ (void)disableBackupForFilePath:(NSString *)path;

+ (_Nullable id)fetchImageWithName:(NSString *)assetName withCompletionHandler:(void (^)(UIImage *image))completionHandler;

+ (NSArray *)listFilesInCacheDirectoryWithExtension:(NSString *)extension withSubpath:(NSString *)subpath;

// methods to override
- (void)finishedDownloadingAsset:(NSDictionary *)assetDict;
- (void)failedDownloadingAsset:(NSDictionary *)assetDict;
- (BOOL)determineLoginFailure:(id)postprocessedData; // warning: this method is being called from one of the worker threads
- (void)reauthenticateWithCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler;
- (NSString *)reachabilityHost;

@end

NS_ASSUME_NONNULL_END

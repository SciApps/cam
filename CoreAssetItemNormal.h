//
//  CoreAssetItemNormal.h
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetManager.h"
@import util;

NS_ASSUME_NONNULL_BEGIN

@interface CoreAssetItemNormal<KeyType, ObjectType> : NSObject

@property (nonatomic, strong) OKOMutableWeakArray* assetCompletionHandlers;
@property (nonatomic, strong) OKOMutableWeakArray* assetFailureHandlers;
@property (nonatomic, assign) NSUInteger priorLevel;
@property (nonatomic, assign) NSUInteger retryCount;
@property (nonatomic, strong) KeyType assetName;
@property (nonatomic, readonly) BOOL shouldCache;
@property (nonatomic, readonly) BOOL shouldCacheOnDisk;
@property (nonatomic, readonly) BOOL retrieveCachedObjectOnFailure;
@property (nonatomic, readonly) NSTimeInterval cacheMaxAge;

+ (NSUInteger)workerThreads;
+ (Class)parentCamClass;

+ (NSString *)assetStorageDirectory;
- (NSString *)fileSystemPath;
- (NSString *)cacheIdentifier;

- (NSData *)load;
- (void)store:(NSData *)assetData;
- (void)removeStoredFile;
- (NSDate *)storedFileModificationDate;
- (BOOL)storedFileCachingAgeExpired;

- (NSURLRequest *)createURLRequest;

- (id)addCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler;
- (void)sendCompletionHandlerMessages:(id)data;

- (id)addFailureHandler:(CoreAssetManagerFailureBlock)completionHandler;
- (void)sendFailureHandlerMessages:(NSError *)reason;

- (_Nullable ObjectType)postProcessData:(NSData *)assetData;

- (void)sendPostProcessedDataToHandlers:(ObjectType)postprocessedData;
- (void)sendFailureOnMainThreadToHandlers:(NSError *)reason;

+ (_Nullable id)fetchAssetWithName:(KeyType)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler;
+ (_Nullable id)fetchAssetWithName:(KeyType)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler;

+ (void)recursive_generateCollectionIdentifier:(id)collection identifier:(NSMutableString *)identifier;
+ (NSString *)safelyGeneratedCollectionPath:(id)collection;

@end

NS_ASSUME_NONNULL_END

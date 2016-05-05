//
//  CoreAssetItemNormal.m
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import "CoreAssetItemNormal.h"
#import "UtilMacros.h"

@implementation CoreAssetItemNormal

- (BOOL)shouldCache {
    return _assetCompletionHandlers.count > 0;
}

- (BOOL)shouldCacheOnDisk {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if ([self isKindOfClass:[object class]]) {
        return [_assetName isEqual:[object assetName]];
    }
    
    return NO;
}

+ (NSUInteger)workerThreads {
    return 1;
}

+ (Class)parentCamClass {
    return CoreAssetManager.class;
}

+ (NSString *)assetStorageDirectory {
    NSString *directoryPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    directoryPath = [directoryPath stringByAppendingString:@"/assets/"];
    return directoryPath;
}

- (NSString *)fileSystemPath {
    return [[CoreAssetItemNormal assetStorageDirectory] stringByAppendingPathComponent:_assetName];
}

- (NSString *)cacheIdentifier {
    if ([self.assetName isKindOfClass:NSString.class]) {
        return [NSStringFromClass(self.class) stringByAppendingString:self.assetName];
    }
    else if ([self.assetName respondsToSelector:@selector(hash)]) {
        return [NSStringFromClass(self.class) stringByAppendingFormat:@"%lu", ((NSString *)self.assetName).hash];
    }
    
    return nil;
}

- (NSData *)load {
    NSError *err = nil;
    NSData *input = [NSData dataWithContentsOfFile:[self fileSystemPath] options:NSDataReadingMappedIfSafe error:&err];
    
    if (err) {
        TestLog(@"CoreAssetItem load: file loading failed");
        @throw [NSException exceptionWithName:err.localizedDescription reason:err.localizedFailureReason userInfo:err.userInfo];
    }
    
    return input;
}

- (void)store:(NSData *)assetData {
    if (assetData.length) {
        NSString *assetPath = [self fileSystemPath];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *err = nil;
        
        NSString *dir = [assetPath stringByDeletingLastPathComponent];
        
        if([fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&err]) {
            [fileManager createFileAtPath:assetPath contents:assetData attributes:nil];
            [CoreAssetManager disableBackupForFilePath:assetPath];
        }
        else {
            TestLog(@"CoreAssetItem store: createDirectoryAtPath failed");
            @throw [NSException exceptionWithName:err.localizedDescription reason:err.localizedFailureReason userInfo:err.userInfo];
        }
    }
}

- (void)removeStoredFile {
    [[NSFileManager defaultManager] removeItemAtPath:[self fileSystemPath] error:nil];
}

- (NSURLRequest *)createURLRequest {
    TestLog(@"CoreAssetItemNormal createURLRequest: implement me");
    return nil;
}

- (id)addCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler {
    [_assetCompletionHandlers compact];
    
    if (completionHandler) {
        if (!_assetCompletionHandlers) {
            _assetCompletionHandlers = [OKOMutableWeakArray new];
        }
        
        return [_assetCompletionHandlers addObjectReturnRef:completionHandler];
    }
    
    return nil;
}

- (void)sendCompletionHandlerMessages:(id)data {
    [_assetCompletionHandlers compact];
    
    for (CoreAssetManagerCompletionBlock block in _assetCompletionHandlers) {
        block(data);
    }
    
    _assetCompletionHandlers = nil;
    _assetFailureHandlers = nil;
}

- (id)addFailureHandler:(CoreAssetManagerFailureBlock)completionHandler {
    [_assetFailureHandlers compact];
    
    if (completionHandler) {
        if (!_assetFailureHandlers) {
            _assetFailureHandlers = [OKOMutableWeakArray new];
        }
        
        return [_assetFailureHandlers addObjectReturnRef:completionHandler];
    }
    
    return nil;
}

- (void)sendFailureHandlerMessages:(NSError *)reason {
    [_assetFailureHandlers compact];
    
    for (CoreAssetManagerFailureBlock block in _assetFailureHandlers) {
        block(reason);
    }
    
    _assetFailureHandlers = nil;
    _assetCompletionHandlers = nil;
}

- (id)postProcessData:(NSData *)assetData {
    return assetData;
}

- (void)sendPostProcessedDataToHandlers:(id)postprocessedData {
    if (self.assetCompletionHandlers.count || self.assetFailureHandlers.count) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self performSelectorOnMainThread:@selector(sendCompletionHandlerMessages:) withObject:postprocessedData waitUntilDone:NO];
        });
    }
}

- (void)sendFailureOnMainThreadToHandlers:(NSError *)reason {
    if (self.assetCompletionHandlers.count || self.assetFailureHandlers.count) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self performSelectorOnMainThread:@selector(sendFailureHandlerMessages:) withObject:reason waitUntilDone:NO];
        });
    }
}

+ (id)fetchAssetWithName:(id)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler {
    return [[self.parentCamClass manager] fetchAssetDataClass:self.class forAssetName:assetName withCompletionHandler:completionHandler];
}

+ (id)fetchAssetWithName:(id)assetName withCompletionHandler:(CoreAssetManagerCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler {
    return [[self.parentCamClass manager] fetchAssetDataClass:self.class forAssetName:assetName withCompletionHandler:completionHandler withFailureHandler:failureHandler];
}

@end

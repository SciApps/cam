//
//  CoreAssetItemNormal.m
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import "CoreAssetItemNormal.h"

@implementation CoreAssetItemNormal

- (BOOL)shouldCache {
    return _assetCompletionHandlers.count > 0;
}

- (BOOL)isEqual:(id)object {
    if ([self isKindOfClass:[object class]]) {
        return [_assetName isEqualToString:[object assetName]];
    }
    
    return NO;
}

+ (NSUInteger)workerThreads {
    return 1;
}

+ (NSString *)assetStorageDirectory {
    NSString *directoryPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    directoryPath = [directoryPath stringByAppendingString:@"/assets/"];
    return directoryPath;
}

- (NSString *)fileSystemPath {
    return [[CoreAssetItemNormal assetStorageDirectory] stringByAppendingPathComponent:_assetName];
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
}

- (id)postProcessData:(NSData *)assetData {
    return assetData;
}

- (void)sendPostProcessedDataToHandlers:(id)postprocessedData {
    if (self.assetCompletionHandlers.count) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self performSelectorOnMainThread:@selector(sendCompletionHandlerMessages:) withObject:postprocessedData waitUntilDone:NO];
        });
    }
}

@end

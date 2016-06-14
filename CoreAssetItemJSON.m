//
//  CoreAssetItemJSON.m
//  CoreAssetManager
//
//  Created by Bálint Róbert on 12/04/16.
//  Copyright (c) 2016 IncepTech Ltd All rights reserved.
//

#import "CoreAssetItemJSON.h"

@implementation CoreAssetItemJSON

+ (NSUInteger)workerThreads {
    return 4;
}

- (NSString *)fileSystemPath {
    NSString *generatedPath = [CoreAssetItemNormal safelyGeneratedCollectionPath:super.assetName];
    NSString *fsPath = [[CoreAssetItemNormal assetStorageDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"json/%@.%@.json", NSStringFromClass(self.class), generatedPath]];
    return fsPath;
}

- (NSURLRequest *)createURLRequest {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    
    TestLog(@"%@ %@: implement me", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    
    return request;
}

- (NSData *)serializeRequestJSON {
    NSError *error;
    id jsonData = [NSJSONSerialization dataWithJSONObject:super.assetName options:0 error:&error];
    
    if (error || !jsonData) {
        TestLog(@"%@ %@: JSON serialization error: '%@'", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error.localizedDescription);
    }
    
    return jsonData;
}

+ (nullable NSData *)serializeRequestJSONWithInput:(id)input {
    NSError *error;
    id jsonData = [NSJSONSerialization dataWithJSONObject:input options:0 error:&error];
    
    if (error || !jsonData) {
        TestLog(@"%@ %@: JSON serialization error: '%@'", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error.localizedDescription);
    }
    
    return jsonData;
}

- (id)postProcessData:(NSData *)assetData {
    NSError *error;
    id jsonData = [NSJSONSerialization JSONObjectWithData:assetData options:0 error:&error];
    
    if (error || !jsonData) {
        TestLog(@"%@ %@: JSON de-serialization error: '%@'", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error.localizedDescription);
    }
    
    return jsonData;
}

@end

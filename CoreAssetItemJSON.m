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
    NSString *fsPath = [[CoreAssetItemNormal assetStorageDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"json/%@", super.assetName]];
    return [fsPath stringByAppendingString:@""];
}

- (NSURLRequest *)createURLRequest {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    
    TestLog(@"%@ %@: implement me", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    
    return request;
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

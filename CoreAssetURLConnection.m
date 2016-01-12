//
//  CoreAssetURLConnection.m
//  FinTech
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 IncepTech Ltd All rights reserved.
//

#import "CoreAssetURLConnection.h"
//#import "CoreAssetItemPDF.h"
#import "CoreAssetItemImage.h"

@implementation CoreAssetURLConnection

- (instancetype)init {
    self = [super init];
    
    if (self) {
        [self initialize];
    }
    
    return self;
}

- (void)initialize {
    _assetItem = nil;
    _connectionData = nil;
    _connectionDataExpectedLength = 0;
}

- (void)appendData:(NSData *)data {
    if (!_connectionData) {
        NSUInteger sizeHint = 64 * 1024;
        
        if (_connectionDataExpectedLength) {
            sizeHint = (NSUInteger)_connectionDataExpectedLength;
        }
        else {
            /*if ([assetItem isKindOfClass:[CoreAssetItemPDF class]]) {
                sizeHint = 1 * 1024 * 1024;
            }
            else */if ([_assetItem isKindOfClass:[CoreAssetItemImage class]]) {
                sizeHint = 128 * 1024;
            }
        }
        
        _connectionData = [[NSMutableData alloc] initWithCapacity:sizeHint];
    }
    
    [_connectionData appendData:data];
}

- (void)appendBytes:(const void *)bytes length:(NSUInteger)length {
    if (!_connectionData) {
        NSUInteger sizeHint = 64 * 1024;
        
        if (_connectionDataExpectedLength) {
            sizeHint = (NSUInteger)_connectionDataExpectedLength;
        }
        else {
            /*if ([assetItem isKindOfClass:[CoreAssetItemPDF class]]) {
                sizeHint = 1 * 1024 * 1024;
            }
            else */if ([_assetItem isKindOfClass:[CoreAssetItemImage class]]) {
                sizeHint = 128 * 1024;
            }
        }
        
        _connectionData = [[NSMutableData alloc] initWithCapacity:sizeHint];
    }
    
    [_connectionData appendBytes:bytes length:length];
}

- (BOOL)validLength {
    if (!_connectionDataExpectedLength) {
        return YES;
    }
    
    return _connectionData.length == _connectionDataExpectedLength;
}

@end

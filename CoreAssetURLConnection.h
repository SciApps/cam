//
//  CoreAssetURLConnection.h
//  FinTech
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 IncepTech Ltd All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetItemNormal.h"

@interface CoreAssetURLConnection : NSObject

@property (nonatomic, strong) CoreAssetItemNormal *assetItem;
@property (nonatomic, assign) long long connectionDataExpectedLength;
@property (nonatomic, strong) NSMutableData *connectionData;

- (void)appendData:(NSData *)data;
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length;
- (BOOL)validLength;

@end

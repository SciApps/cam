//
//  CoreAssetItemJSON.h
//  CoreAssetManager
//
//  Created by Bálint Róbert on 12/04/16.
//  Copyright (c) 2016 IncepTech Ltd All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetItemNormal.h"

NS_ASSUME_NONNULL_BEGIN

@interface CoreAssetItemJSON : CoreAssetItemNormal

- (NSString *)fileSystemPath;

- (NSURLRequest *)createURLRequest;

- (id)postProcessData:(NSData *)assetData;

@end

NS_ASSUME_NONNULL_END

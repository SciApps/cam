//
//  CoreAssetItemImage.h
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 IncepTech Ltd All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetItemNormal.h"

NS_ASSUME_NONNULL_BEGIN

@interface CoreAssetItemErrorImage : UIImage

@end

typedef void (^CoreAssetItemImageCompletionBlock)(UIImage *assetData);

@interface CoreAssetItemImage : CoreAssetItemNormal

- (NSString *)fileSystemPath;

- (NSURLRequest *)createURLRequest;

- (id)postProcessData:(NSData *)assetData;

+ (_Nullable id)fetchAssetWithName:(NSString *)assetName withCompletionHandler:(CoreAssetItemImageCompletionBlock)completionHandler;
+ (_Nullable id)fetchAssetWithName:(NSString *)assetName withCompletionHandler:(CoreAssetItemImageCompletionBlock)completionHandler withFailureHandler:(CoreAssetManagerFailureBlock)failureHandler;

@end

NS_ASSUME_NONNULL_END

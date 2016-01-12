//
//  CoreAssetItemImage.h
//  FinTech
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 IncepTech Ltd All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreAssetItemNormal.h"

@interface CoreAssetItemErrorImage : UIImage

@end

@interface CoreAssetItemImage : CoreAssetItemNormal

- (NSString *)fileSystemPath;

- (NSURLRequest *)createURLRequest;

- (id)postProcessData:(NSData *)assetData;

@end

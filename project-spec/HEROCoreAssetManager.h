//
//  HEROCoreAssetManager.h
//  cam-test
//
//  Created by mrnuku on 2016. 01. 17..
//  Copyright © 2016. mrnuku. All rights reserved.
//

#import "CoreAssetManager.h"

@interface HEROCoreAssetManager : CoreAssetManager

- (void)fetchImageAssetListFromImages:(NSArray *)images startDownload:(BOOL)startDownload;

@end

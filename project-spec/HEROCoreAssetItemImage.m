//
//  HEROCoreAssetItemImage.m
//  cam-test
//
//  Created by mrnuku on 2016. 01. 17..
//  Copyright © 2016. mrnuku. All rights reserved.
//

#import "HEROCoreAssetItemImage.h"
#import "NetworkingConstants.h"

@implementation HEROCoreAssetItemImage

+ (NSDictionary *)attributedFormatForError {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    
    return @{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont fontWithName:fontBold size:44], NSParagraphStyleAttributeName:paragraph};
}

- (NSURLRequest *)createURLRequest {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    
    NSURL * baseUrl = [NSURL URLWithString:kBaseUrlStr];
    NSURL * imageAssetEndPointUrl = [baseUrl URLByAppendingPathComponent:kImageAssetEndPointStr];
    NSURL * imageAssetUrl = [imageAssetEndPointUrl URLByAppendingPathComponent:super.assetName];
    
    [request setURL: imageAssetUrl];
    [request setHTTPMethod:@"GET"];
    
    return request;
}

@end
